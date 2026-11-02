import { ChangeEvent, DragEvent, PointerEvent as ReactPointerEvent, useEffect, useMemo, useRef, useState } from 'react';
import { loadMediaRecords, loadProjectSnapshot, saveMediaRecord, saveProjectSnapshot } from './localProjectDB';

type MediaKind = 'Vídeo' | 'Imagem' | 'Áudio';
type MediaItem = {
  id: string;
  name: string;
  size: number;
  kind: MediaKind;
  url: string;
  duration?: number;
  file: File;
  order: number;
};
type Clip = { id: string; mediaId: string; track: string; start: number; duration: number; sourceIn?: number; label: string };
type Message = { id: string; role: 'ai' | 'user'; text: string };
type PendingDecision = { title: string; detail: string; options: string[] };

const navItems = [
  { id: 'director', icon: '✳', label: 'Diretor IA' },
  { id: 'media', icon: '▧', label: 'Mídia' },
  { id: 'captions', icon: 'T', label: 'Legendas' },
  { id: 'audio', icon: '♫', label: 'Áudio' },
  { id: 'motion', icon: '◈', label: 'Motion' },
  { id: 'color', icon: '◉', label: 'Cor' },
  { id: 'styles', icon: '▦', label: 'Estilos' },
];

const initialMessages: Message[] = [{
  id: 'welcome', role: 'ai',
  text: 'Sou o Diretor IA. Importe seus arquivos e me diga o que pretende produzir. Vou respeitar a ordem de envio, analisar a narrativa e pedir sua aprovação antes de decisões importantes, especialmente cortes de sonoras.'
}];

const fmt = (seconds: number) => {
  const m = Math.floor(seconds / 60).toString().padStart(2, '0');
  const s = Math.floor(seconds % 60).toString().padStart(2, '0');
  return `${m}:${s}`;
};
const formatBytes = (bytes: number) => bytes < 1024 * 1024 ? `${(bytes / 1024).toFixed(0)} KB` : `${(bytes / (1024 * 1024)).toFixed(1)} MB`;

const probeDuration = (url: string, kind: MediaKind) => new Promise<number | undefined>(resolve => {
  if (kind === 'Imagem') return resolve(5);
  const element = document.createElement(kind === 'Áudio' ? 'audio' : 'video');
  element.preload = 'metadata';
  element.onloadedmetadata = () => { const duration = Number.isFinite(element.duration) ? element.duration : undefined; element.src = ''; resolve(duration); };
  element.onerror = () => resolve(undefined);
  element.src = url;
});

export default function App() {
  const [activeTab, setActiveTab] = useState('director');
  const [profile, setProfile] = useState('Institucional');
  const [projectName, setProjectName] = useState('Projeto sem título');
  const [renaming, setRenaming] = useState(false);
  const [media, setMedia] = useState<MediaItem[]>([]);
  const [clips, setClips] = useState<Clip[]>([]);
  const [selectedClip, setSelectedClip] = useState<string | null>(null);
  const [messages, setMessages] = useState<Message[]>(initialMessages);
  const [prompt, setPrompt] = useState('');
  const [playing, setPlaying] = useState(false);
  const [playhead, setPlayhead] = useState(0);
  const [zoom, setZoom] = useState(100);
  const [pending, setPending] = useState<PendingDecision | null>(null);
  const [approved, setApproved] = useState<string[]>([]);
  const [captionStyle, setCaptionStyle] = useState('Palavra destacada');
  const [musicMood, setMusicMood] = useState('Emocional institucional');
  const [motionPreset, setMotionPreset] = useState('Tipografia cinética');
  const [colorLook, setColorLook] = useState('Institucional natural');
  const [status, setStatus] = useState('Projeto local');
  const [dragging, setDragging] = useState(false);
  const [hydrated, setHydrated] = useState(false);
  const timelineRef = useRef<HTMLDivElement>(null);
  const clipDragRef = useRef<{ id: string; pointerId: number; startX: number; originalStart: number; originalClips: Clip[]; moved: boolean } | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const videoRef = useRef<HTMLVideoElement>(null);
  const undoStackRef = useRef<Clip[][]>([]);
  const redoStackRef = useRef<Clip[][]>([]);

  const selectedClipData = clips.find(clip => clip.id === selectedClip) ?? null;
  const selectedMedia = media.find(item => item.id === selectedClipData?.mediaId) ?? media[0];
  const totalDuration = useMemo(() => Math.max(110, clips.reduce((max, clip) => Math.max(max, clip.start + clip.duration), 0)), [clips]);
  const totalSize = useMemo(() => media.reduce((sum, item) => sum + item.size, 0), [media]);
  const timelineScale = zoom * 0.08;
  const timelineWidth = Math.max(760, totalDuration * timelineScale);
  const rulerMarks = Array.from({ length: Math.ceil(totalDuration / 10) + 1 }, (_, index) => index * 10);

  useEffect(() => {
    let cancelled = false;
    const restore = async () => {
      try {
        const [snapshot, storedMedia] = await Promise.all([loadProjectSnapshot(), loadMediaRecords()]);
        if (cancelled) return;
        if (snapshot) {
          setProjectName(snapshot.projectName || 'Projeto sem título');
          setProfile(snapshot.profile || 'Institucional');
          setClips(snapshot.clips || []);
        }
        const restored: MediaItem[] = storedMedia
          .sort((a, b) => a.order - b.order)
          .map(record => {
            const file = new File([record.blob], record.name, { type: record.type, lastModified: record.lastModified });
            return { id: record.id, name: record.name, size: record.size, kind: record.kind, url: URL.createObjectURL(record.blob), file, order: record.order, duration: record.duration };
          });
        setMedia(restored);
      } catch (error) {
        if (!cancelled) setStatus(`Armazenamento local indisponível: ${error instanceof Error ? error.message : 'erro desconhecido'}`);
      } finally {
        if (!cancelled) setHydrated(true);
      }
    };
    void restore();
    return () => { cancelled = true; };
  }, []);

  useEffect(() => {
    if (!hydrated) return;
    const snapshot = {
      schemaVersion: 3,
      projectName,
      profile,
      media: media.map(({ id, name, size, kind, order, duration }) => ({ id, name, size, kind, order, duration })),
      clips,
      updatedAt: new Date().toISOString(),
    };
    const handle = window.setTimeout(() => {
      void saveProjectSnapshot(snapshot).then(() => setStatus('Projeto salvo localmente')).catch(error => setStatus(`Falha no autosalvamento: ${error instanceof Error ? error.message : 'erro'}`));
    }, 350);
    return () => window.clearTimeout(handle);
  }, [hydrated, projectName, profile, media, clips]);

  useEffect(() => {
    if (!playing || selectedMedia?.kind === 'Vídeo') return;
    const timer = window.setInterval(() => setPlayhead(value => value >= totalDuration ? 0 : value + 0.25), 250);
    return () => window.clearInterval(timer);
  }, [playing, totalDuration, selectedMedia?.kind]);

  useEffect(() => {
    if (selectedMedia?.kind === 'Vídeo' && videoRef.current && videoRef.current.src !== selectedMedia.url) {
      videoRef.current.src = selectedMedia.url;
      videoRef.current.load();
    }
  }, [selectedMedia]);

  useEffect(() => {
    if (selectedMedia?.kind !== 'Vídeo' || !videoRef.current) return;
    const sourceOffset = Math.max(0, (selectedClipData?.sourceIn ?? 0) + playhead - (selectedClipData?.start ?? 0));
    if (Math.abs(videoRef.current.currentTime - sourceOffset) > 0.75) videoRef.current.currentTime = sourceOffset;
  }, [selectedClipData?.id, selectedClipData?.sourceIn, playhead]);

  const addFiles = async (fileList: FileList | File[]) => {
    const incoming = Array.from(fileList).filter(file => file.type.startsWith('video/') || file.type.startsWith('image/') || file.type.startsWith('audio/'));
    if (!incoming.length) return;
    const created: MediaItem[] = incoming.map((file, index) => ({
      id: `${Date.now()}-${index}-${Math.random().toString(36).slice(2, 7)}`,
      name: file.name,
      size: file.size,
      kind: file.type.startsWith('video/') ? 'Vídeo' : file.type.startsWith('image/') ? 'Imagem' : 'Áudio',
      url: URL.createObjectURL(file),
      file,
      order: media.length + index + 1,
    }));
    let persisted = true;
    try {
      await Promise.all(created.map(item => saveMediaRecord({ id: item.id, name: item.name, size: item.size, type: item.file.type, lastModified: item.file.lastModified, kind: item.kind, order: item.order, blob: item.file })));
    } catch (error) {
      persisted = false;
      setStatus(`Mídia disponível nesta sessão, mas não foi persistida: ${error instanceof Error ? error.message : 'erro'}`);
    }
    setMedia(prev => [...prev, ...created]);
    setClips(prev => {
      let cursor = prev.reduce((max, clip) => Math.max(max, clip.start + clip.duration), 0);
      const next = [...prev];
      created.forEach(item => {
        const estimated = item.kind === 'Imagem' ? 5 : item.kind === 'Áudio' ? 20 : 12;
        next.push({ id: `clip-${item.id}`, mediaId: item.id, track: item.kind === 'Áudio' ? 'audio' : 'video', start: cursor, duration: estimated, label: item.name });
        cursor += estimated;
      });
      return next;
    });
    created.forEach(async item => {
      const actualDuration = await probeDuration(item.url, item.kind);
      if (!actualDuration || actualDuration <= 0) return;
      setMedia(current => current.map(entry => entry.id === item.id ? { ...entry, duration: actualDuration } : entry));
      void saveMediaRecord({ id: item.id, name: item.name, size: item.size, type: item.file.type, lastModified: item.file.lastModified, kind: item.kind, order: item.order, duration: actualDuration, blob: item.file });
      const fallbackDuration = item.kind === 'Imagem' ? 5 : item.kind === 'Áudio' ? 20 : 12;
      setClips(current => current.map(clip => clip.mediaId === item.id && Math.abs(clip.duration - fallbackDuration) < 0.001 ? { ...clip, duration: actualDuration } : clip));
    });
    setActiveTab('media');
    setStatus(persisted ? `${incoming.length} arquivo(s) salvos no armazenamento local. Lendo duração real da mídia...` : `${incoming.length} arquivo(s) importados apenas nesta sessão. Verifique o espaço e as permissões de armazenamento.`);
  };

  const onInputChange = (event: ChangeEvent<HTMLInputElement>) => {
    if (event.target.files) void addFiles(event.target.files);
    event.target.value = '';
  };
  const onDrop = (event: DragEvent<HTMLDivElement>) => {
    event.preventDefault(); setDragging(false); void addFiles(event.dataTransfer.files);
  };

  const addMessage = (role: Message['role'], text: string) => setMessages(prev => [...prev, { id: `${Date.now()}-${Math.random()}`, role, text }]);
  const sendPrompt = () => {
    const value = prompt.trim();
    if (!value) return;
    addMessage('user', value);
    addMessage('ai', 'Recebi sua orientação. Esta versão registra o comando e prepara o fluxo de aprovação. O modelo de IA local ainda será integrado. Não vou alterar sonoras ou decisões narrativas importantes sem mostrar a proposta primeiro.');
    setPrompt('');
    setActiveTab('director');
  };

  const createInstitutionalProposal = () => {
    if (!media.length) {
      addMessage('ai', 'Antes de propor a montagem, importe os vídeos e áudios da pauta. Vou manter a ordem original dos arquivos como referência cronológica.');
      setActiveTab('director');
      return;
    }
    setPending({
      title: 'Confirme a estrutura institucional',
      detail: 'A proposta considera abertura de aproximadamente 8 segundos, sonoras com cobertura em B-roll e encerramento institucional. Nenhuma fala será cortada nesta etapa.',
      options: ['Morador primeiro, prefeito no final', 'Autoridade primeiro, prefeito no final', 'Misturar as sonoras conforme a narrativa']
    });
  };

  const decide = (option: string) => {
    setApproved(prev => [...prev, option]);
    addMessage('user', `Aprovação: ${option}`);
    addMessage('ai', 'Estrutura aprovada como orientação. A próxima etapa será transcrever as sonoras e apresentar os trechos sugeridos para sua revisão antes de qualquer corte.');
    setPending(null);
  };

  const rememberTimeline = () => {
    undoStackRef.current.push(clips.map(clip => ({ ...clip })));
    if (undoStackRef.current.length > 40) undoStackRef.current.shift();
    redoStackRef.current = [];
  };

  const undoTimeline = () => {
    const previous = undoStackRef.current.pop();
    if (!previous) return;
    redoStackRef.current.push(clips.map(clip => ({ ...clip })));
    setClips(previous);
    setStatus('Última alteração desfeita');
  };

  const redoTimeline = () => {
    const next = redoStackRef.current.pop();
    if (!next) return;
    undoStackRef.current.push(clips.map(clip => ({ ...clip })));
    setClips(next);
    setStatus('Alteração refeita');
  };

  const updateSelectedClip = (patch: Partial<Clip>) => {
    if (!selectedClip) return;
    rememberTimeline();
    setClips(prev => prev.map(clip => clip.id === selectedClip ? { ...clip, ...patch } : clip));
    setStatus('Alteração aplicada à timeline');
  };

  const splitSelectedClip = () => {
    const clip = clips.find(item => item.id === selectedClip);
    if (!clip) { setStatus('Selecione um clipe primeiro'); return; }
    const offset = playhead - clip.start;
    if (offset < 0.5 || offset > clip.duration - 0.5) {
      setStatus('Posicione o cursor dentro do clipe para dividir');
      return;
    }
    rememberTimeline();
    const right: Clip = { ...clip, id: `clip-${Date.now()}`, sourceIn: (clip.sourceIn ?? 0) + offset, start: playhead, duration: clip.duration - offset, label: `${clip.label} · parte 2` };
    setClips(prev => prev.flatMap(item => item.id === clip.id ? [{ ...item, duration: offset }, right] : [item]));
    setSelectedClip(right.id);
    setStatus('Clipe dividido no ponto de reprodução');
  };

  const duplicateSelectedClip = () => {
    if (!selectedClipData) return;
    rememberTimeline();
    const copy: Clip = { ...selectedClipData, id: `clip-${Date.now()}`, start: selectedClipData.start + selectedClipData.duration, label: `${selectedClipData.label} · cópia` };
    setClips(prev => [...prev, copy]);
    setSelectedClip(copy.id);
    setStatus('Clipe duplicado');
  };

  const deleteSelectedClip = () => {
    if (!selectedClip) return;
    rememberTimeline();
    setClips(prev => prev.filter(clip => clip.id !== selectedClip));
    setSelectedClip(null);
    setStatus('Clipe removido da timeline. Arquivo original preservado.');
  };

  const nudgeSelectedClip = (seconds: number) => {
    if (!selectedClipData) return;
    updateSelectedClip({ start: Math.max(0, selectedClipData.start + seconds) });
  };

  const adjustSelectedDuration = (seconds: number) => {
    if (!selectedClipData) return;
    const sourceDuration = selectedMedia?.duration ?? Number.POSITIVE_INFINITY;
    const maxDuration = Math.max(0.5, sourceDuration - (selectedClipData.sourceIn ?? 0));
    updateSelectedClip({ duration: Math.min(maxDuration, Math.max(0.5, selectedClipData.duration + seconds)) });
  };

  const trimSelectedStart = (seconds: number) => {
    if (!selectedClipData) return;
    const amount = Math.max(-(selectedClipData.sourceIn ?? 0), Math.min(seconds, selectedClipData.duration - 0.5));
    if (Math.abs(amount) < 0.001) return;
    updateSelectedClip({ sourceIn: Math.max(0, (selectedClipData.sourceIn ?? 0) + amount), duration: selectedClipData.duration - amount });
    setStatus('Ponto de entrada ajustado sem alterar o arquivo original');
  };

  const trimSelectedEnd = (seconds: number) => {
    if (!selectedClipData) return;
    const sourceDuration = selectedMedia?.duration ?? Number.POSITIVE_INFINITY;
    const maxDuration = Math.max(0.5, sourceDuration - (selectedClipData.sourceIn ?? 0));
    const nextDuration = Math.min(maxDuration, Math.max(0.5, selectedClipData.duration + seconds));
    updateSelectedClip({ duration: nextDuration });
    setStatus('Ponto de saída ajustado sem alterar o arquivo original');
  };

  const seekTimeline = (clientX: number, rect: DOMRect) => {
    const seconds = Math.max(0, Math.min(totalDuration, (clientX - rect.left) / timelineScale));
    setPlayhead(seconds);
    const clip = clips.find(item => item.track === 'video' && seconds >= item.start && seconds < item.start + item.duration);
    if (clip) setSelectedClip(clip.id);
    else setPlaying(false);
  };

  const beginClipDrag = (event: ReactPointerEvent<HTMLButtonElement>, clip: Clip) => {
    event.stopPropagation();
    event.currentTarget.setPointerCapture(event.pointerId);
    clipDragRef.current = { id: clip.id, pointerId: event.pointerId, startX: event.clientX, originalStart: clip.start, originalClips: clips.map(item => ({ ...item })), moved: false };
    setSelectedClip(clip.id);
  };

  const moveClipDrag = (event: ReactPointerEvent<HTMLButtonElement>) => {
    const drag = clipDragRef.current;
    if (!drag || drag.pointerId !== event.pointerId) return;
    const delta = event.clientX - drag.startX;
    if (Math.abs(delta) > 3) drag.moved = true;
    if (!drag.moved) return;
    const nextStart = Math.max(0, drag.originalStart + delta / timelineScale);
    setClips(current => current.map(item => item.id === drag.id ? { ...item, start: nextStart } : item));
  };

  const finishClipDrag = (event: ReactPointerEvent<HTMLButtonElement>) => {
    const drag = clipDragRef.current;
    if (!drag || drag.pointerId !== event.pointerId) return;
    if (drag.moved) {
      undoStackRef.current.push(drag.originalClips);
      if (undoStackRef.current.length > 40) undoStackRef.current.shift();
      redoStackRef.current = [];
      setStatus('Clipe reposicionado na timeline');
    }
    clipDragRef.current = null;
  };

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null;
      if (target && ['INPUT', 'TEXTAREA', 'SELECT'].includes(target.tagName)) return;
      if (event.code === 'Space') { event.preventDefault(); setPlaying(value => !value); }
      if ((event.key === 'Delete' || event.key === 'Backspace') && selectedClip) deleteSelectedClip();
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'z') { event.preventDefault(); event.shiftKey ? redoTimeline() : undoTimeline(); }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  });

  const exportProject = () => {
    const payload = {
      schemaVersion: 1,
      projectName,
      profile,
      createdAt: new Date().toISOString(),
      media: media.map(({ id, name, size, kind, order }) => ({ id, name, size, kind, order })),
      clips,
      note: 'Pacote de estrutura do projeto. Os arquivos originais de mídia não estão incorporados.'
    };
    const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a'); a.href = url; a.download = `${projectName.replace(/[^a-z0-9-_]/gi, '_')}.editor-ia.json`; a.click(); URL.revokeObjectURL(url);
    setStatus('Estrutura do projeto exportada');
  };

  const renderToolPanel = () => {
    switch (activeTab) {
      case 'media': return <div className="tool-content"><div className="tool-title"><div><span className="eyebrow">BIBLIOTECA DO PROJETO</span><h2>Mídia e organização</h2></div><button className="primary small" onClick={() => fileInputRef.current?.click()}>＋ Importar</button></div><div className={`media-drop ${dragging ? 'dragging' : ''}`} onDragOver={e => { e.preventDefault(); setDragging(true); }} onDragLeave={() => setDragging(false)} onDrop={onDrop} onClick={() => fileInputRef.current?.click()}><span className="drop-icon">⇧</span><b>Adicione vídeos, fotos e áudios</b><small>A ordem de importação será preservada como referência cronológica.</small></div><div className="media-list">{media.map(item => <button key={item.id} className={`media-row ${selectedMedia?.id === item.id ? 'selected' : ''}`} onClick={() => { const clip = clips.find(c => c.mediaId === item.id); if (clip) setSelectedClip(clip.id); }}><span className={`media-kind ${item.kind.toLowerCase()}`}>{item.kind === 'Vídeo' ? '▶' : item.kind === 'Imagem' ? '▧' : '♫'}</span><span className="media-name"><b>{item.order.toString().padStart(2, '0')} · {item.name}</b><small>{item.kind} · {formatBytes(item.size)}</small></span><span className="media-order">#{item.order}</span></button>)}</div></div>;
      case 'captions': return <div className="tool-content"><div className="tool-title"><div><span className="eyebrow">TEXTO E SINCRONIZAÇÃO</span><h2>Central de legendas</h2></div><span className="local-tag">MODELO LOCAL FUTURO</span></div><div className="settings-grid"><label>Estilo de legenda<select value={captionStyle} onChange={e => setCaptionStyle(e.target.value)}><option>Palavra destacada</option><option>Karaoke</option><option>Cinematográfica minimalista</option><option>Institucional discreta</option><option>Hormozi inspirado</option></select></label><label>Posicionamento<select><option>Inferior central</option><option>Centro</option><option>Superior</option><option>Dinâmico por cena</option></select></label><label>Palavra em destaque<select><option>Amarelo</option><option>Azul</option><option>Branco</option><option>Personalizada</option></select></label><label>Animação<select><option>Pop suave</option><option>Entrada por palavra</option><option>Typewriter</option><option>Slide</option><option>Sem animação</option></select></label></div><div className="caption-preview"><span>PRÉVIA DO ESTILO</span><strong>UMA NOVA HISTÓRIA <em>COMEÇA AQUI.</em></strong><small>{captionStyle} · exemplo visual</small></div><p className="muted-note">A transcrição e a sincronização automáticas serão conectadas ao modelo local de reconhecimento de fala. Nenhum áudio será enviado para a nuvem.</p></div>;
      case 'audio': return <div className="tool-content"><div className="tool-title"><div><span className="eyebrow">SOUND DIRECTOR IA</span><h2>Desenho sonoro</h2></div><span className="local-tag">OFFLINE FIRST</span></div><div className="settings-grid"><label>Intenção musical<select value={musicMood} onChange={e => setMusicMood(e.target.value)}><option>Emocional institucional</option><option>Épica e inspiradora</option><option>Documental natural</option><option>Animada e festiva</option><option>Suspense crescente</option></select></label><label>Intensidade<select><option>Progressiva</option><option>Discreta</option><option>Alta</option><option>Dinâmica</option></select></label></div><div className="sound-layers"><div><span className="layer-icon music">♫</span><div><b>Trilha musical</b><small>{musicMood}</small></div><span className="layer-state">Preparada</span></div><div><span className="layer-icon voice">◖</span><div><b>Voz e sonoras</b><small>Prioridade máxima sobre a música</small></div><span className="layer-state">Protegida</span></div><div><span className="layer-icon sfx">✧</span><div><b>Efeitos sonoros</b><small>Inserção contextual, sem exageros</small></div><span className="layer-state">Assistido</span></div></div><button className="secondary wide" onClick={() => addMessage('ai', `Preferência de desenho sonoro registrada: ${musicMood}. A análise acústica local será implementada no motor de áudio.`)}>Registrar preferência sonora</button></div>;
      case 'motion': return <div className="tool-content"><div className="tool-title"><div><span className="eyebrow">COMPOSIÇÃO E ANIMAÇÃO</span><h2>Motion studio</h2></div><span className="local-tag">KEYFRAMES</span></div><div className="preset-grid">{['Tipografia cinética', 'Palavras no fundo', 'Lower thirds', 'Títulos cinematográficos', 'Logo animada', 'Transições'].map(p => <button key={p} className={`preset-card ${motionPreset === p ? 'chosen' : ''}`} onClick={() => setMotionPreset(p)}><span>◈</span><b>{p}</b><small>{p === 'Palavras no fundo' ? 'Texto atrás do assunto' : 'Composição editável'}</small></button>)}</div><div className="selection-note">Selecionado: <b>{motionPreset}</b>. Cada elemento deverá permanecer editável e possuir keyframes próprios.</div></div>;
      case 'color': return <div className="tool-content"><div className="tool-title"><div><span className="eyebrow">COLOR STUDIO</span><h2>Cor e acabamento</h2></div><span className="local-tag">LOCAL</span></div><label className="wide-label">Look inicial<select value={colorLook} onChange={e => setColorLook(e.target.value)}><option>Institucional natural</option><option>Cinematográfico quente</option><option>Documental neutro</option><option>Contraste suave</option><option>Personalizado</option></select></label><div className="color-controls">{['Exposição', 'Contraste', 'Saturação', 'Temperatura', 'Realces', 'Sombras'].map((item, index) => <label key={item}>{item}<input type="range" min="-100" max="100" defaultValue={index === 1 ? 12 : 0}/></label>)}</div><p className="muted-note">Controles demonstrativos. A aplicação real será feita por clipe no pipeline de cor local.</p></div>;
      case 'styles': return <div className="tool-content"><div className="tool-title"><div><span className="eyebrow">CENTRAL DE ESTILOS</span><h2>Perfis de edição</h2></div></div><div className="style-list">{['Institucional e Prefeitura', 'Entrevistas e depoimentos', 'Eventos e festas', 'Vídeos virais', 'Documentário e storytelling', 'Publicidade e comerciais', 'Story Mode'].map(name => <button key={name} className={`style-option ${profile === name.replace(' e Prefeitura', '') ? 'selected' : ''}`} onClick={() => setProfile(name.includes('Prefeitura') ? 'Institucional' : name)}><span className="style-symbol">✳</span><span><b>{name}</b><small>Regras de narrativa, ritmo, áudio, cor e legendas</small></span><span className="arrow">↗</span></button>)}</div></div>;
      case 'settings': return <div className="tool-content"><div className="tool-title"><div><span className="eyebrow">PREFERÊNCIAS DO APLICATIVO</span><h2>Configurações</h2></div></div><div className="settings-grid"><label>Dispositivo principal<select><option>iPhone e iPad</option><option>iPad</option><option>iPhone</option></select></label><label>Modo de operação<select><option>Offline prioritário</option><option>Offline estrito</option></select></label><label>Resolução padrão<select><option>4K quando suportado</option><option>1080p</option></select></label><label>Taxa de quadros<select><option>30 FPS</option><option>24 FPS</option><option>60 FPS</option></select></label></div><p className="muted-note">Esta tela registra preferências de protótipo. A integração nativa com armazenamento, permissões e modelos locais será feita nas próximas etapas.</p></div>;
      default: return <div className="tool-content"><div className="tool-title"><div><span className="eyebrow">DIREÇÃO E MONTAGEM</span><h2>Diretor IA</h2></div><span className="local-tag">LOCAL FIRST</span></div><div className="director-summary"><div className="director-symbol">✳</div><div><b>Seu assistente de produção</b><p>Descreva o vídeo, selecione um perfil ou importe a mídia. O Diretor IA deverá analisar, propor e pedir sua aprovação quando houver dúvida.</p></div></div><div className="quick-actions"><button onClick={createInstitutionalProposal}><span>▤</span><b>Montagem institucional</b><small>8 segundos de abertura, sonoras e encerramento</small></button><button onClick={() => setPending({ title: 'Como deseja organizar os takes?', detail: 'A sequência de importação será preservada. A IA pode sugerir intercalações sem alterar a cronologia sem sua autorização.', options: ['Preservar ordem estritamente', 'Intercalar planos mantendo cronologia', 'Analisar e perguntar antes de reorganizar'] })}><span>⇄</span><b>Organizar takes</b><small>Respeitar a ordem original dos arquivos</small></button><button onClick={() => setPending({ title: 'Defina a prioridade sonora', detail: 'A IA analisará as falas, mas não cortará nenhuma sonora sem apresentar a transcrição e o trecho sugerido.', options: ['Morador ou beneficiário', 'Autoridade responsável', 'Prefeito no encerramento'] })}><span>◖</span><b>Planejar sonoras</b><small>Transcrição e aprovação antes dos cortes</small></button></div><div className="conversation"><div className="conversation-head"><b>Conversa com o Diretor IA</b><span>Comandos em português</span></div><div className="conversation-messages">{messages.map(message => <div key={message.id} className={`chat-message ${message.role}`}><span>{message.role === 'ai' ? '✳' : 'EU'}</span><p>{message.text}</p></div>)}</div><div className="composer"><textarea value={prompt} onChange={e => setPrompt(e.target.value)} onKeyDown={e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); sendPrompt(); } }} placeholder="Ex.: monte um vídeo institucional de 1min30, respeitando a ordem dos arquivos..."/><button onClick={sendPrompt} disabled={!prompt.trim()}>Enviar ↑</button></div></div></div>;
    }
  };

  return <div className="studio-shell">
    <header className="topbar"><div className="brand"><div className="brand-mark">✳</div><div><b>EDITOR <span>IA</span></b><small>LOCAL CREATIVE STUDIO</small></div></div><div className="project-title">{renaming ? <input autoFocus value={projectName} onChange={e => setProjectName(e.target.value)} onBlur={() => setRenaming(false)} onKeyDown={e => e.key === 'Enter' && setRenaming(false)}/> : <button onClick={() => setRenaming(true)}>{projectName} <span>✎</span></button>}<small>● {status}</small></div><div className="top-actions"><span className="offline-indicator"><i/> OFFLINE FIRST</span><button className="secondary" onClick={() => fileInputRef.current?.click()}>＋ Importar</button><button className="primary" onClick={exportProject}>Exportar projeto</button></div></header>
    <aside className="sidebar"><div className="side-label">WORKSPACE</div>{navItems.map(item => <button key={item.id} className={`nav-button ${activeTab === item.id ? 'active' : ''}`} onClick={() => setActiveTab(item.id)}><span>{item.icon}</span>{item.label}{item.id === 'director' && <i/>}</button>)}<div className="sidebar-bottom"><div className="device-status"><span>⌁</span><div><b>Processamento local</b><small>Arquitetura offline-first</small></div><strong>✓</strong></div><button className={`nav-button ${activeTab === 'settings' ? 'active' : ''}`} onClick={() => setActiveTab('settings')}><span>⚙</span>Configurações</button></div></aside>
    <main className="main-content"><section className="page-heading"><div><div className="eyebrow">ESTÚDIO DE EDIÇÃO <span>/</span> {profile.toUpperCase()}</div><h1>Seu próximo vídeo começa aqui.</h1><p>IA como diretora. Você no controle de cada decisão.</p></div><label className="profile-picker">PERFIL DE EDIÇÃO<select value={profile} onChange={e => setProfile(e.target.value)}><option>Institucional</option><option>Entrevista</option><option>Evento</option><option>Vídeo viral</option><option>Documentário</option><option>Story Mode</option></select></label></section>
      <div className="workspace-grid"><section className="panel monitor-panel"><div className="panel-heading"><div><small>MONITOR</small><b>Pré-visualização</b></div><div className="monitor-meta"><span>16:9</span><span>prévia local</span></div></div><div className="monitor-screen">{selectedMedia?.kind === 'Vídeo' ? <video ref={videoRef} controls={false} playsInline onTimeUpdate={e => setPlayhead((selectedClipData?.start ?? 0) + e.currentTarget.currentTime - (selectedClipData?.sourceIn ?? 0))} /> : selectedMedia?.kind === 'Imagem' ? <img src={selectedMedia.url} alt="Prévia da mídia selecionada"/> : <div className="empty-monitor"><span>▣</span><b>{selectedMedia ? 'Arquivo de áudio selecionado' : 'Seu vídeo aparecerá aqui'}</b><small>{selectedMedia?.name ?? 'Importe arquivos para começar'}</small></div>}<span className="monitor-time">{fmt(playhead)} / {fmt(totalDuration)}</span></div><div className="transport-bar"><button onClick={() => { setPlaying(false); setPlayhead(0); if (videoRef.current) videoRef.current.currentTime = 0; }}>◀◀</button><button className="transport-play" onClick={() => { const next = !playing; setPlaying(next); if (videoRef.current) next ? void videoRef.current.play() : videoRef.current.pause(); }}>{playing ? 'Ⅱ' : '▶'}</button><button onClick={() => setPlayhead(Math.min(totalDuration, playhead + 5))}>▶▶</button><span>{fmt(playhead)}</span><div className="transport-spacer"/><span className="monitor-meta">Prévia local</span></div></section>
      <section className="panel tool-panel">{renderToolPanel()}</section></div>
      <section className="panel timeline-panel"><div className="timeline-heading"><div><small>MONTAGEM PROFISSIONAL</small><b>Timeline <span>{clips.length} clipes</span></b></div><div className="timeline-controls"><button onClick={undoTimeline} disabled={!undoStackRef.current.length} title="Desfazer">↶</button><button onClick={redoTimeline} disabled={!redoStackRef.current.length} title="Refazer">↷</button><button onClick={() => setZoom(Math.max(50, zoom - 10))}>−</button><span>{zoom}%</span><button onClick={() => setZoom(Math.min(180, zoom + 10))}>＋</button><button onClick={() => setZoom(100)}>Ajustar</button></div></div><div className="timeline-scroll" ref={timelineRef}><div className="timeline-ruler" style={{ minWidth: `${timelineWidth + 145}px` }}><span>TRILHAS</span><div className="ruler-lane" style={{ width: `${timelineWidth}px` }} onPointerDown={event => seekTimeline(event.clientX, event.currentTarget.getBoundingClientRect())}>{rulerMarks.map(mark => <span key={mark} style={{ left: `${mark * timelineScale}px` }}>{fmt(mark)}</span>)}</div></div>{[{id:'video',name:'VÍDEO PRINCIPAL',color:'blue'},{id:'broll',name:'B-ROLL',color:'teal'},{id:'captions',name:'LEGENDAS',color:'purple'},{id:'audio',name:'TRILHA MUSICAL',color:'amber'},{id:'sfx',name:'EFEITOS SONOROS',color:'rose'}].map(track => <div className="timeline-track" key={track.id}><div className="track-name"><i className={track.color}/>{track.name}</div><div className="track-lane" style={{ width: `${timelineWidth}px`, minWidth: `${timelineWidth}px` }} onPointerDown={event => seekTimeline(event.clientX, event.currentTarget.getBoundingClientRect())}>{clips.filter(clip => track.id === 'video' ? clip.track === 'video' : clip.track === track.id).map(clip => <button key={clip.id} className={`timeline-clip ${track.color} ${selectedClip === clip.id ? 'selected' : ''}`} style={{ left: `${clip.start * timelineScale}px`, width: `${Math.max(24, clip.duration * timelineScale)}px` }} onPointerDown={event => beginClipDrag(event, clip)} onPointerMove={moveClipDrag} onPointerUp={finishClipDrag} onPointerCancel={finishClipDrag} onClick={event => { event.stopPropagation(); setSelectedClip(clip.id); setPlayhead(clip.start); }} title={`${clip.label} · arraste para mover`}>{clip.label}</button>)}{track.id === 'audio' && media.some(item => item.kind === 'Áudio') && <span className="track-placeholder">Áudio importado</span>}<div className="playhead-line" style={{ left: `${playhead * timelineScale}px` }}/></div></div>)}</div>{selectedClipData && <div className="clip-inspector"><div className="clip-inspector-heading"><b>Inspetor de clipe</b><span>{fmt(selectedClipData.start)} · {selectedClipData.duration.toFixed(1)}s</span></div><div className="clip-inspector-grid"><label>Nome<input value={selectedClipData.label} onChange={e => updateSelectedClip({ label: e.target.value })}/></label><label>Trilha<select value={selectedClipData.track} onChange={e => updateSelectedClip({ track: e.target.value })}><option value="video">Vídeo principal</option><option value="broll">B-roll</option><option value="captions">Legendas</option><option value="audio">Trilha musical</option><option value="sfx">Efeitos sonoros</option></select></label></div><div className="clip-actions"><button onClick={splitSelectedClip}>✂ Dividir no cursor</button><button onClick={duplicateSelectedClip}>▣ Duplicar</button><button onClick={() => nudgeSelectedClip(-1)}>← 1s</button><button onClick={() => nudgeSelectedClip(1)}>1s →</button><button onClick={() => adjustSelectedDuration(-1)}>− Duração</button><button onClick={() => adjustSelectedDuration(1)}>+ Duração</button><button onClick={() => trimSelectedStart(0.5)}>Aparar início +0,5s</button><button onClick={() => trimSelectedEnd(-0.5)}>Aparar final −0,5s</button><button className="danger" onClick={deleteSelectedClip}>Excluir</button></div><p className="timeline-hint">Dica: arraste o clipe para reposicionar. Toque na régua ou na trilha para mover o cursor de reprodução.</p></div>}<div className="timeline-bottom"><span>● {fmt(playhead)}</span><span>Ordem de importação preservada</span><span>FPS 30</span></div></section>
      <div className="lower-grid"><section className="panel media-panel"><div className="panel-heading"><div><small>ARQUIVOS DO PROJETO</small><b>Mídia <span>{media.length}</span></b></div><button className="secondary small" onClick={() => fileInputRef.current?.click()}>＋ Adicionar</button></div>{media.length ? <div className="media-list">{media.map(item => <button key={item.id} className={`media-row ${selectedMedia?.id === item.id ? 'selected' : ''}`} onClick={() => { const clip = clips.find(c => c.mediaId === item.id); if (clip) { setSelectedClip(clip.id); setPlayhead(clip.start); } }}><span className={`media-kind ${item.kind.toLowerCase()}`}>{item.kind === 'Vídeo' ? '▶' : item.kind === 'Imagem' ? '▧' : '♫'}</span><span className="media-name"><b>{item.order.toString().padStart(2, '0')} · {item.name}</b><small>{item.kind} · {formatBytes(item.size)}</small></span><span className="media-order">#{item.order}</span></button>)}</div> : <button className="empty-library" onClick={() => fileInputRef.current?.click()}><span>⇧</span><b>Importar mídia</b><small>Vídeos, fotos e áudios do dispositivo</small></button>}<div className="media-footer">{media.length} arquivos · {formatBytes(totalSize)} nesta sessão</div></section><section className="panel workflow-panel"><div className="panel-heading"><div><small>FLUXO DE PRODUÇÃO</small><b>Etapas do projeto</b></div><span className="local-tag">01 / 04</span></div>{['Importar e organizar','Analisar com IA local','Aprovar roteiro e sonoras','Editar e finalizar'].map((step, i) => <div className={`workflow-row ${i === 0 ? 'current' : ''}`} key={step}><span>{String(i + 1).padStart(2, '0')}</span><div><b>{step}</b><small>{['Preservar sequência original','Transcrever, reconhecer cenas e sons','Revisar cortes antes de aplicar','Motion, cor, mixagem e exportação'][i]}</small></div>{i === 0 && <i>●</i>}</div>)}</section></div>
      <footer className="studio-footer"><span>EDITOR IA STUDIO · PROTÓTIPO 0.7</span><span>Interface local demonstrativa · motores nativos em desenvolvimento</span></footer>
    </main>
    <input ref={fileInputRef} type="file" accept="video/*,image/*,audio/*" multiple hidden onChange={onInputChange}/>
    {pending && <div className="modal-layer"><div className="decision-modal"><span className="eyebrow">DIRETOR IA · PRECISO DA SUA ORIENTAÇÃO</span><h2>{pending.title}</h2><p>{pending.detail}</p><div className="decision-options">{pending.options.map(option => <button key={option} onClick={() => decide(option)}>{option}<span>↗</span></button>)}</div><button className="cancel-decision" onClick={() => setPending(null)}>Voltar sem decidir</button></div></div>}
  </div>;
}
