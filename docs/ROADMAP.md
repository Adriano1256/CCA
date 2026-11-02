# Roadmap

## v0.10
- Local PCM audio analysis using AVAssetReader.
- RMS/peak envelope and waveform preview.
- Adjustable silence threshold and minimum pause duration.
- Candidate pauses shown for review; no automatic destructive edits.

## Next engineering milestones
1. macOS/Xcode compile, fix SDK-level issues and test export on physical devices.
2. Unit tests for timeline operations, project persistence, PCM calculations and silence grouping.
3. Timeline playback and compositing parity between preview and export.
4. Motion Studio: editable text styles, word-level captions, keyframes, masks and person segmentation.
5. Local speech model for consistent offline transcription and speaker segmentation.
6. Local vision model for shot classification, faces/person tracking and B-roll suggestions.
7. Sound Director: sound-event classification, music structure analysis, SFX cue suggestions, ducking envelopes and user approval.
8. Local language model for Director IA command interpretation and project-aware editing plans.
9. Device benchmarks: memory, thermal behavior, battery, codecs, render speed and model latency.
10. TestFlight beta after successful Xcode build and physical-device validation.

## Product constraints
- iPhone and iPad native apps are the primary deliverables.
- Core editing must not require network access.
- Cloud may be used only for optional transfer, backup or updates with explicit authorization.
- No destructive AI edit without reversible operations; ambiguous narrative decisions require user approval.


## v0.14
- On-device Vision person segmentation for still photographs.
- Transparent PNG cutout stored locally as a generated media asset.
- Dedicated `subject` timeline track and compositor z-order for text-behind-person compositions in still images.
- No cloud processing and no destructive change to the source photograph.

## Next engineering milestones
1. Add temporal person segmentation for video and track mask continuity frame by frame.
2. Add user-adjustable mask refinement and feathering controls.
3. Add a preview compositor that matches export z-order.
4. Continue with local model integration for Director IA, sound-event understanding and semantic video analysis.

## Atualização v0.15
- [x] Pré-processamento local de segmentação de pessoas em vídeos por amostragem.
- [x] Exportar máscaras PNG com timestamps e manifesto JSON.
- [ ] Tracking temporal para estabilizar identidade e contorno entre quadros.
- [ ] Converter máscaras em sequência alfa contínua para o compositor.
- [ ] Integrar a sequência alfa à timeline e ao exportador multipista.


## v0.18
- [x] Guardar o manifesto após segmentação local de vídeo.
- [x] Converter as máscaras amostradas em clipes PNG transparentes na trilha `subject`.
- [x] Sincronizar cada máscara ao tempo do clipe original, incluindo `sourceIn`.
- [x] Usar o z-order existente para compor pessoa acima de textos.
- [ ] Substituir a sequência amostrada por segmentação/propagação temporal de maior frequência.
- [ ] Adicionar refinamento de máscara, feather, decontaminação de borda e seleção manual da pessoa.
- [ ] Testar visualmente a exportação no iPhone/iPad com Xcode.


## v0.19
- [x] Adicionar feather configurável às máscaras de pessoa em vídeo.
- [x] Persistir o raio de suavização no manifesto de segmentação.
- [x] Manter leitura de manifestos antigos sem o campo novo.
- [ ] Comparar qualidade do recorte em cabelo, movimento rápido e fundos complexos em aparelho real.
- [ ] Implementar refinamento temporal e tracking denso antes de elevar a segmentação a qualidade de produção.

## v0.21
- [x] Extract a Foundation-only Director planning core for deterministic narrative rules.
- [x] Generate an institutional draft with an 8-second chronological opening, sonora review candidates, B-roll candidates and a closing placeholder.
- [x] Generate Stories drafts with visual segments capped at 15 seconds and longer audio preserved for review.
- [x] Display draft segments in the Director IA panel without mutating the timeline.
- [x] Add executable tests for order, opening duration, Stories cap and long-audio exception.
- [ ] Replace metadata-only B-roll candidates with local semantic video analysis.
- [ ] Identify speakers and transcribe embedded video audio before proposing sonora trims.
- [ ] Connect approved draft segments to reversible timeline operations.


## Concluído na v0.22
- Converter rascunhos de montagem em clipes reais, editáveis e não destrutivos na timeline.
- Acrescentar a montagem ao final do conteúdo existente, preservar sonoras integrais e bloquear automaticamente cortes visuais de Stories que exigem revisão.
- Cobertura B-roll sugerida em sincronia com sonoras e prevenção de aplicação duplicada.

## Próximas prioridades técnicas
1. Prévia de reprodução composta com a mesma ordem de camadas do render final.
2. Análise audiovisual local para identificar fala embutida em vídeo, falantes, assunto e melhores trechos com contexto.
3. Integração de modelos locais de linguagem, visão e áudio com medição de memória, latência, bateria e temperatura em dispositivos-alvo.
4. Motor de renderização multipista com transições, áudio original e música independentes, overlays animados e máscaras temporais.
5. Build no Xcode, testes de unidade/UI e testes de desempenho em iPhone e iPad reais.


## Atualização v0.23
- [x] Extrair matemática do ducking para núcleo Foundation testável.
- [x] Cobrir união, recorte temporal, envelope e entradas inválidas com testes automatizados.
- [ ] Ligar intervalos de fala verificados pelo usuário ao mixer sem depender exclusivamente das legendas.
- [ ] Adicionar classificação local de fontes sonoras (voz, música, ambiente e efeitos) com modelo adequado e benchmark em dispositivos.
- [ ] Validar rampas e mixagem em exportações reais no iPhone/iPad.


## Atualização v0.24
- [x] Corrigir erros de compilação conhecidos e o caminho de mídia da exportação.
- [x] Construtor único de composição para prévia e exportação.
- [x] Interface compacta para iPhone, timeline única e vários projetos.
- [x] Sonora em vídeo, B-roll mudo e retorno à pessoa no rascunho institucional.
- [x] Aprovação e exportação de Stories em arquivos.
- [x] CI que gera IPA e abre o app no simulador.
- [ ] Confirmar build no Xcode e corrigir o que o SDK apontar.
- [ ] Testar exportação real em iPhone e iPad.
- [ ] Tela de aprovação de corte de fala com transcrição e contexto.
- [ ] Modelo local de linguagem e gerenciador de modelos.
