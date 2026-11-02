# Editor IA Studio · v0.24

Editor de vídeo **nativo para iPhone e iPad**, local-first/offline-first. O protótipo React é uma bancada auxiliar de fluxos e não substitui o aplicativo SwiftUI.

- Para instalar: `INSTALAR_NO_IPHONE.md`
- Bugs corrigidos, novidades e limites reais desta versão: `AUDITORIA_v0.23.md`

## Novidades da versão 0.14 · Recorte local de pessoa em fotografias

- Novo `PersonSegmentationService` com `VNGeneratePersonSegmentationRequest` do Vision.
- Segmentação processada no próprio aparelho, sem envio da fotografia para a nuvem.
- Geração de PNG com transparência usando máscara de pessoa e Core Image.
- O Motion Studio oferece o comando de recorte quando uma fotografia está selecionada.
- O recorte é adicionado como clipe na faixa `subject`, alinhado ao clipe original.
- O compositor organiza a ordem visual: fotografia de fundo, textos/legendas e pessoa recortada por cima. Isso permite que textos fiquem visualmente atrás da pessoa em fotografias.
- Limitação explícita: esta entrega segmenta fotografias estáticas. Segmentação de vídeo quadro a quadro, tracking e atualização temporal da máscara ainda não estão implementados.

## Novidades da versão 0.13 · Animação palavra por palavra

- Novo campo `wordAnimation` em elementos de texto, com migração compatível.
- Modo `wordPop`: divide o texto em palavras e cria camadas de texto independentes.
- Cada palavra recebe entrada escalonada com opacidade e escala, renderizada localmente pelo Core Animation.
- Controle do modo no Motion Studio e persistência no projeto.
- Limite de 12 palavras para esse modo; textos maiores usam o renderizador convencional para evitar composições excessivas.

## Novidades da versão 0.12 · Motion Studio inicial

- Elementos de texto com posição horizontal e vertical normalizadas.
- Escala e rotação dos textos.
- Tamanho de fonte, cor e contorno configuráveis.
- Animações de entrada Fade, Pop, Slide e Bounce.
- Ajustes editáveis no painel Motion Studio e persistidos no JSON local.
- Renderização dos novos parâmetros de texto na composição AVFoundation/Core Animation.
- Migração compatível: projetos antigos recebem valores padrão para os novos campos.

## Recursos já presentes na base

### iOS/iPadOS
- Interface SwiftUI adaptável a iPhone e iPad.
- Importação de vídeos, imagens e áudio via Arquivos e Fototeca.
- Cópia dos originais para armazenamento local do app.
- Projeto JSON local e timeline não destrutiva.
- Seleção, divisão, duplicação, exclusão, trim, movimentação, volume, fades e histórico.
- Keyframes básicos de opacidade, escala e volume em clipes.
- Exportação local inicial por AVFoundation para mídia compatível, textos e legendas.
- Transcrição experimental via Speech framework, condicionada ao suporte offline do dispositivo e idioma.
- Análise acústica local por AVAssetReader: envelope RMS, pico e pausas candidatas.
- Ducking inicial de trilhas independentes baseado nos intervalos de legendas/transcrição.
- Motion Studio inicial: posição, escala, rotação, cor, contorno e animações de entrada para textos.
- Segmentação local de pessoas em fotografias e composição de camada transparente acima da tipografia (v0.14).

### Protótipo web
- React + TypeScript + Vite em `src/`.
- IndexedDB para armazenamento local do protótipo.
- Não é a aplicação final iOS/iPadOS.

## Executar protótipo web

Requer Node.js 20 ou superior.

```bash
npm install
npm run dev
```

## Gerar projeto Xcode

Requer macOS, Xcode 15+ e XcodeGen.

```bash
brew install xcodegen
xcodegen generate --spec project.yml
open EditorIA.xcodeproj
```

Configure a equipe de assinatura no Xcode para instalar em aparelhos físicos. O workflow GitHub Actions disponível é apenas um ponto de partida para build de simulador, não gera IPA assinado automaticamente.

## Validação desta entrega

- `swiftc -frontend -parse native-ios/EditorIA/*.swift` executado com sucesso nesta entrega.
- JSON de `package.json` validado.
- Arquivos de configuração YAML validados.
- Não foi executado build Xcode/iOS porque este ambiente não possui macOS nem SDK iOS.
- Não foi executado build web porque `node_modules` não está instalado.

## Limitações importantes

- Diretor IA ainda não possui LLM local integrado para comandos complexos.
- Transcrição Speech é experimental e não garante funcionamento offline uniforme em todos os dispositivos; ainda falta integrar um modelo local próprio.
- Sound Director mede energia e pausas, mas ainda não classifica semanticamente eventos, emoções ou fontes sonoras.
- Ducking usa intervalos de legendas/transcrição como aproximação de fala e, nesta versão, atua em trilhas de áudio independentes; não reduz automaticamente o áudio original embutido em vídeo.
- Segmentação de pessoas em fotografias está disponível de forma inicial; segmentação em vídeo, tracking quadro a quadro e máscaras animadas ainda não implementados.
- Motion Studio atual não possui keyframes de texto, animação palavra por palavra, tracking ou composição 3D.
- Remotion e HyperFrames ainda não estão integrados ao app nativo; o compositor inicial usa AVFoundation/Core Animation.
- Colorização avançada, LUTs 3D, curvas e matching de câmeras ainda não implementados.
- A prévia não reproduz ainda todas as camadas e animações exatamente como a exportação.
- É necessário testar codecs, frame rates, orientações, áudio multicanal, arquivos longos, memória, temperatura e bateria em iPhone/iPad reais.

## Próximas etapas

1. Criar testes automatizados para migração de projeto, timeline, overlays e renderização.
2. Compilar no Xcode e corrigir issues de SDK/concorrência.
3. Expandir segmentação de fotografias para vídeo quadro a quadro, tracking e composição em camadas com profundidade.
4. Implementar keyframes de texto, tracking e animações por palavra.
5. Desenvolver motor de áudio com classificação local de sons, voz, música e efeitos.
6. Integrar modelos locais de linguagem, fala, visão e áudio com benchmarks de memória e bateria.
7. Validar renderização em iPhone e iPad físicos e preparar TestFlight.

## Novidades da versão 0.15 · Máscaras de pessoa em vídeo (pré-processamento)

- Novo `VideoPersonSegmentationService` usando `AVAssetReader` e `VNGeneratePersonSegmentationRequest`.
- Analisa vídeo localmente e gera PNGs transparentes em amostragem configurável (1 a 12 quadros por segundo; interface inicial usa 5 fps).
- Salva um `manifest.json` com nome do arquivo de origem, duração, taxa de amostragem, quantidade de quadros e timestamp de cada máscara.
- O Motion Studio oferece a ação **Gerar máscaras do vídeo** quando um vídeo está selecionado.
- As máscaras ficam na pasta local `Media/PersonMasks/` do projeto; nenhum vídeo é enviado à nuvem.
- Esta etapa gera os ativos temporais para o futuro compositor. Ainda não cria um clipe alfa contínuo nem aplica automaticamente o recorte sobre a timeline. A amostragem de 5 fps é adequada para análise/prototipagem, não para rotoscopia final em movimento rápido.

## Validação da versão 0.15

- `swiftc -frontend -parse native-ios/EditorIA/*.swift` executado com sucesso neste ambiente.
- Build de Xcode e teste de Vision/AVAssetReader em dispositivo físico continuam pendentes por ausência de macOS/Xcode neste ambiente.


### v0.18: aplicar sequência de máscaras de vídeo à timeline
- O Motion Studio agora mantém o manifesto da segmentação de vídeo após a análise.
- Novo comando aplica os PNGs transparentes como clipes na trilha `subject`, sincronizados ao tempo do clipe original e respeitando `sourceIn`/duração.
- Os recortes ficam acima dos textos na composição de exportação, permitindo testar texto atrás da pessoa em vídeo.
- Processamento e arquivos permanecem locais.
- Limitação conhecida: a sequência usa a taxa de amostragem (atualmente 5 fps na interface). Os quadros são mantidos até a próxima amostra; movimentos rápidos podem apresentar saltos. Isto ainda não é tracking denso nem segmentação por frame a 30/60 fps.
- Para qualidade de produção, ainda faltam interpolação/propagação temporal, refinamento de bordas, controle de identidade quando há várias pessoas, prévia em tempo real e validação no Xcode/dispositivo.

## Novidades da versão 0.19 · Refinamento de bordas das máscaras

- Controle de feather da máscara de pessoa em vídeo diretamente no Motion Studio (0 a 8 px na interface).
- O serviço limita o raio efetivo a 12 px para reduzir custo e evitar halos excessivos.
- Suavização da máscara com Core Image Gaussian Blur antes da composição do PNG transparente.
- O manifesto passa a registrar `maskFeatherRadius` para documentar como a sequência foi gerada.
- Compatibilidade retroativa: manifestos anteriores sem `maskFeatherRadius` continuam sendo lidos e recebem valor padrão 0.
- Processamento permanece local no aparelho. O feather melhora a transição da borda, mas não substitui refinamento semântico, tracking denso nem segmentação a 30/60 fps.


## Validação da versão 0.19

- Análise sintática Swift executada com sucesso (`swiftc -frontend -parse`).
- JSON do `package.json` validado.
- Build Xcode e teste visual das máscaras continuam pendentes por ausência de macOS/Xcode neste ambiente.

## Novidades da versão 0.20 · Planejador local do Diretor IA

- Novo `LocalDirectorService` que interpreta comandos comuns em português por regras locais, sem rede e sem enviar dados para servidores.
- Reconhece intenções iniciais de edição institucional e Stories e produz um plano estruturado com perfil, duração-alvo, sequência narrativa e avisos.
- Reforça regras do projeto: ordem de importação como referência, abertura institucional de aproximadamente 8 segundos, sonoras com cobertura visual, encerramento institucional e Stories com limite de 15 segundos para segmentos apenas visuais.
- Marca explicitamente cortes de fala e desenho sonoro como decisões que exigem aprovação.
- A interface do Diretor IA agora exibe o plano e as limitações detectadas; gerar o plano não altera a timeline nem executa cortes.
- Importante: esta é uma camada determinística de planejamento, não um LLM. A integração de um modelo de linguagem local para comandos livres e raciocínio multimodal continua pendente.

## Validação da versão 0.20

- Análise sintática dos arquivos Swift executada com `swiftc -frontend -parse`.
- Validação do JSON de `package.json` e do YAML de `project.yml`.
- Build Xcode, execução do app e testes em iPhone/iPad físicos ainda dependem de macOS, Xcode e dispositivos Apple.

## Novidades da versão 0.21 · Rascunho de timeline do Diretor IA

- Novo núcleo `DirectorPlanningCore.swift`, independente de SwiftUI/AVFoundation e compilável com Foundation.
- O Diretor IA agora transforma a análise institucional em um rascunho de sequência com blocos de abertura, candidatas a sonora, imagens de cobertura e placeholder de encerramento.
- A abertura institucional distribui até 8 segundos entre os primeiros arquivos visuais respeitando `importOrder`.
- Sonoras em arquivos de áudio são preservadas integralmente no rascunho e marcadas para revisão obrigatória. Nenhum corte de fala é aplicado.
- O planejador de Stories divide segmentos visuais em blocos de no máximo 15 segundos e preserva arquivos de áudio mais longos como sonoras que exigem revisão.
- A interface exibe o rascunho com início, duração, origem e alertas de revisão. O rascunho não altera a timeline nem os originais.
- Foram adicionados testes automatizados independentes para ordem de importação, abertura de 8 segundos, limite visual de 15 segundos e exceção de áudio longo.

## Validação da versão 0.21

- `swiftc native-ios/EditorIA/DirectorPlanningCore.swift tests/DirectorPlanningCoreTests.swift -o /tmp/director-core-tests` compilado com sucesso neste ambiente Linux.
- Executado `DirectorPlanningCoreTests`: 4 verificações passaram.
- `swiftc -frontend -parse native-ios/EditorIA/*.swift` passou para os arquivos Swift do projeto.
- JSON de `package.json` e YAML de `project.yml` validados.
- Build do aplicativo iOS completo e teste em aparelho continuam pendentes de macOS/Xcode e dispositivos Apple. O núcleo puro do planejador, entretanto, foi efetivamente compilado e executado.


## Novidades da versão 0.22 · Aplicação não destrutiva do rascunho à timeline

- Novo `DirectorTimelineMaterializer.swift`, módulo Foundation-only que converte segmentos do Diretor IA em instruções de clipes para a timeline.
- O painel do Diretor IA agora oferece **Adicionar montagem à timeline** quando existe um rascunho institucional ou de Stories.
- A montagem é acrescentada depois do conteúdo atual, em vez de sobrescrever ou reorganizar clipes existentes.
- Os segmentos são distribuídos em trilhas `video`, `broll` e `audio`; cobertura B-roll pode ficar sincronizada por cima da sonora.
- Sonoras candidatas e áudios de Stories entram integralmente, sem cortes automáticos. A transcrição e qualquer edição posterior continuam exigindo revisão.
- Segmentos de vídeo de Stories marcados para revisão não são aplicados automaticamente, pois podem conter fala que precisa ser preservada.
- Cada clipe gerado recebe um marcador estável `[IASEG:...]` para impedir aplicação duplicada do mesmo segmento.
- A operação é registrada no histórico de desfazer/refazer e salva no projeto local. Os arquivos originais permanecem intactos.
- A cobertura visual é uma sugestão estrutural baseada na ordem de importação; a correspondência semântica entre imagem e fala ainda depende do futuro módulo de visão local.

## Validação da versão 0.22

- `DirectorPlanningCore.swift`, `DirectorTimelineMaterializer.swift` e `DirectorPlanningCoreTests.swift` compilados com `swiftc` neste ambiente.
- Sete testes automatizados executados com sucesso: ordem cronológica, abertura de 8 segundos, cobertura sincronizada à sonora, limite de 15 segundos em segmentos visuais de Stories, preservação de áudio longo, aplicação após a timeline existente e prevenção de duplicidade.
- `swiftc -frontend -parse native-ios/EditorIA/*.swift` passou para todos os arquivos Swift do projeto.
- JSON de `package.json` e YAML de `project.yml` validados.
- Build completo de iOS, execução do SwiftUI e exportação AVFoundation continuam pendentes de macOS/Xcode e testes em dispositivos físicos.


## Novidades da versão 0.23 · Núcleo de ducking de áudio testável

- Extraído o cálculo de redução automática de trilha para `AudioDuckingPlanner.swift`, um núcleo puro em Foundation, separado da interface e do AVFoundation.
- O planejador combina intervalos de palavras/legendas próximos, remove intervalos inválidos e converte tempos globais da timeline para tempos relativos a cada clipe de música.
- O renderizador AVFoundation utiliza o mesmo planejador para construir os pontos de automação e calcular o envelope de ataque/recuperação do ducking.
- Ataque padrão de 120 ms e recuperação de 240 ms; intensidade continua configurável no projeto.
- Adicionados cinco testes automatizados para união de falas, interseção com clipes, redução durante fala, recuperação após fala e filtragem de intervalos inválidos.
- Não há análise semântica nova nesta versão: a identificação de fala continua baseada nos intervalos de transcrição/legendas existentes. Nenhum áudio é enviado à nuvem.

## Validação da versão 0.23

- `AudioDuckingPlanner.swift` e `AudioDuckingPlannerTests.swift` compilados com `swiftc` no ambiente disponível; cinco testes passaram.
- Núcleo do Diretor IA e materializador de timeline recompilados; sete testes passaram.
- `swiftc -frontend -parse native-ios/EditorIA/*.swift` passou para todos os arquivos Swift.
- JSON de `package.json` e YAML de `project.yml` validados.
- O build completo iOS/SwiftUI e testes de exportação continuam pendentes de macOS/Xcode e aparelhos Apple físicos.
