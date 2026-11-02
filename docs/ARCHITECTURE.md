# Arquitetura técnica atual

## Camadas

- **App iOS/iPadOS:** SwiftUI. Gerencia navegação, importação, permissões e inspeção.
- **Modelo de projeto:** `EditorProject`, `TimelineClip`, `ClipKeyframe` e `TextOverlay`, serializados em JSON.
- **Armazenamento:** `Application Support/EditorIA`, com mídia copiada para a pasta do projeto.
- **Prévia:** AVPlayer para mídia selecionada. A composição de prévia ainda não é idêntica ao render final.
- **Renderização:** AVMutableComposition, AVMutableVideoComposition e AVVideoCompositionCoreAnimationTool. Todo o processamento ocorre no aparelho.
- **Protótipo web:** React/TypeScript e IndexedDB, usado para validar fluxos e aparência.

## Legendas temporizadas

`CaptionWord` armazena texto, início e duração absolutos na timeline, além de estilo e animação. O serviço `LocalTranscriptionService` usa `SFSpeechURLRecognitionRequest` com `requiresOnDeviceRecognition = true`; se o aparelho não suportar reconhecimento offline para `pt-BR`, a operação falha explicitamente sem fallback de rede. Os segmentos reconhecidos são recortados ao intervalo de mídia selecionado e convertidos para tempo da timeline.

## Modelo de composição

`TimelineClip` referencia um `LocalMedia` por UUID e mantém posição, duração, ponto de entrada, trilha, volume, fades e keyframes. O arquivo original não é modificado.

`TextOverlay` mantém texto, início, duração, tamanho, cor, cor de fundo, posição vertical e animação simples. A versão atual exporta os textos como camadas Core Animation.

## Regras de segurança e controle

- A IA não pode remover nem cortar sonoras sem mostrar transcrição e obter aprovação.
- A ordem de importação é registrada em `LocalMedia.importOrder`.
- A mídia não é enviada para serviços externos.
- A sincronização entre dispositivos não é automática.

## Próxima arquitetura de IA

A camada de IA deverá ser modular: transcrição local, visão computacional, análise acústica, LLM local e agente coordenador. Nenhum modelo foi integrado nesta versão. Antes de escolher modelos, medir consumo de RAM, armazenamento, tempo de inferência, temperatura e autonomia nos dispositivos de destino.

## Sound Director local analysis (v0.10)

`LocalAudioAnalysisService` performs an on-device PCM pass using `AVAssetReader`:

- Downmixes decoded audio to mono 16 kHz signed 16-bit PCM.
- Calculates RMS and peak levels per decoded sample buffer.
- Produces a lightweight waveform series for the UI.
- Detects candidate quiet ranges using a configurable dB threshold and minimum duration.
- Does not delete, trim, or alter media. Silence ranges are suggestions only.
- Runs the decoding pass in a detached task so the SwiftUI main actor remains responsive.

This is signal-level analysis, not semantic sound recognition. It does not yet identify emotion, classify sound events, select music, generate SFX, or perform intelligent ducking. Those require additional local models and listening tests on target devices.

## Audio analysis service (v0.10)

`LocalAudioAnalysisService` decodes the selected asset locally with `AVAssetReader` into mono 16 kHz signed 16-bit PCM. It calculates RMS and peak per decoded sample buffer and groups low-energy buffers into candidate silence intervals. The UI exposes the threshold (dB) and minimum pause length. These ranges are advisory only: the service never edits or removes source media. This is signal analysis, not semantic sound classification or music/SFX selection.


## Person segmentation and depth composition (v0.14)

`PersonSegmentationService` uses Vision's `VNGeneratePersonSegmentationRequest` on-device for a selected still image. It creates a grayscale person mask, blends the original image over a transparent background with Core Image, and writes a transparent PNG into the app's local media folder. The generated asset is added as a `TimelineClip` on the `subject` track at the same timeline position and duration as the source photograph.

The renderer's layer order for this composition is: source still image, text overlays, word captions, then the transparent subject cutout. This produces a basic text-behind-person effect for still photographs. It is not temporal video segmentation: moving subjects, changing masks across frames, occlusion handling and motion tracking remain future work.

## Local Director planning layer (v0.20)

`LocalDirectorService` is a deterministic offline planning layer. It classifies a small set of Portuguese editing intents (institutional and Stories) and creates a structured `LocalDirectorPlan` with a profile, duration target, ordered steps, approval gates and project-specific warnings. It encodes the institutional opening/sonora/coverage/closing rules and the Stories visual-duration rule. The UI displays the plan without modifying the timeline. Speech cuts and sound-design decisions are explicitly marked as requiring approval. This is not an LLM and does not claim semantic understanding of video/audio; a quantized on-device language model and multimodal models remain future integrations.

## Director timeline planning core (v0.21)

`DirectorPlanningCore.swift` is a Foundation-only module so narrative rules can be compiled and tested independently of the iOS SDK. It accepts media descriptors with import order, type and duration, then emits a non-destructive `DirectorTimelineDraft`.

- Institutional draft: allocates up to the first 8 seconds across visual assets in import order, flags standalone audio as a sonora candidate requiring review, preserves visual assets as coverage candidates and adds an explicit institutional-closing placeholder rather than inventing a speaker or selecting a quote.
- Stories draft: splits visual source ranges into segments no longer than 15 seconds; standalone audio is preserved as a longer sonora candidate requiring review. Video segments carry a warning that embedded speech must be analyzed before finalizing the duration exception.
- The SwiftUI Director panel displays the draft but does not apply it to the edit timeline. This is deliberate: no speech edit or narrative reorder is executed without review.
- Automated tests cover chronological ordering, 8-second opening allocation, 15-second visual cap and long-audio preservation.


## Aplicação do rascunho do Diretor IA à timeline (v0.22)

`DirectorTimelineMaterializer` transforma o `DirectorTimelineDraft` em instruções para `TimelineClip`, com mapeamento de papéis para trilhas (`video`, `broll`, `audio`). `ProjectStore.applyDirectorDraft` acrescenta essas instruções ao final do conteúdo existente, registra undo, salva o JSON local e marca cada segmento para impedir aplicação duplicada. A montagem não sobrescreve o material anterior. Áudios de sonora entram com duração integral; segmentos visuais de Stories que exigem revisão não são aplicados automaticamente. A cobertura B-roll sincronizada é uma sugestão cronológica e ainda não usa compreensão semântica da imagem.


## Áudio: planejamento determinístico de ducking (v0.23)

`AudioDuckingPlanner` concentra as operações matemáticas de mixagem automática: união de intervalos próximos, interseção dos intervalos de fala com o tempo de cada clipe musical, geração de pontos de automação e cálculo de envelope com ataque/recuperação. O renderer AVFoundation consome esse núcleo para aplicar rampas de volume. A fonte dos intervalos de fala continua sendo a transcrição/legendas do projeto; RMS e detecção de silêncio não são tratados como reconhecimento semântico de fala.


## v0.24
- `ProjectModel.swift` e `TimelineCore.swift` usam só Foundation e têm testes em `tests/TimelineCoreTests.swift`.
- `TimelineCompositionBuilder` monta a composição para prévia (`TimelinePlayback`) e exportação (`TimelineRenderer`).
- Na exportação, fotos, textos, pessoa e legendas entram por Core Animation. Na prévia, `PreviewLayers` desenha o mesmo empilhamento em SwiftUI, porque `AVPlayerItem` não aceita a ferramenta de animação.
- Projetos ficam em `Application Support/EditorIA/Projects/<id>.json`; a mídia, em `Media/`, fora do backup do iCloud.
