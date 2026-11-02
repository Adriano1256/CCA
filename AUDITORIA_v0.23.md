# Auditoria do código v0.23 e o que mudou na v0.24

## Erros que impediam o app de compilar
- `ContentView`: `specifier:` usado em uma String comum. Só funciona dentro de `Text`.
- `TimelineRenderer`: `setTransformRamp(fromStartTransform:...)`. O nome correto é `fromStart:toEnd:`.
- `project.yml`: `SWIFT_VERSION: "5.9"` não é um modo de linguagem válido. Agora é `5.0`.

## Erros que quebravam o app em uso
- **A exportação nunca funcionava.** O caminho da mídia ficava `Media/Media/arquivo`, nenhum clipe era encontrado.
- **Tela reduzida no iPhone.** Sem tela de abertura declarada, o iOS abre o app em modo de compatibilidade.
- **Vídeo com foto depois falhava.** A composição terminava no último vídeo, mas as instruções iam além.
- **Instruções com microfuros de tempo** por arredondamento, o que invalida a composição. Agora são contíguas.
- **Muitos clipes esgotavam os decodificadores.** Cada clipe criava uma faixa; agora as faixas são reaproveitadas.
- **B-roll entrava com som** por cima da sonora. Agora entra mudo.
- **A sonora em áudio abaixava junto com a música** (ducking). Agora tem trilha de voz própria.
- **Stories não aplicava nada.** Todo vídeo exigia revisão e não havia como aprovar.
- **O Diretor usava máscaras de recorte como se fossem imagens do evento.**
- **Sonora embutida em vídeo não existia para o Diretor**, que é o seu caso comum.
- **Zoom por keyframe saía deslocado** porque a ordem das transformações estava invertida.
- **Aparar o início movia o clipe** na timeline. Agora o fim fica parado.
- **Fotos não podiam durar mais de 5 s.**
- **Fotos e máscaras piscavam** entre quadros.
- **Máscaras de vídeo gravado em pé saíam deitadas.**
- **Status sumia na hora**, porque salvar sobrescrevia a mensagem.
- **Prévia muda** com o iPhone no silencioso.
- **Mídia ia para o backup do iCloud**. Agora fica excluída, seguindo a regra local-first.
- **Interface do iPhone inutilizável:** sete botões em uma linha e cada trilha rolando separada.

## Novo na v0.24
- Layout de iPhone: prévia, timeline e painéis que sobem de baixo. iPad mantém barra lateral.
- Prévia toca a **timeline inteira**, com o mesmo construtor da exportação.
- Timeline única com régua, cursor, zoom de pinça, arrasto com encaixe e alças para aparar.
- Apagar fechando o espaço (ripple).
- Vários projetos: criar, abrir, renomear, apagar.
- Marcar sonora na aba Mídia.
- Montagem institucional: abertura de 8 s, sonora inteira, pessoa 2,5 s, B-roll mudo, retorno à pessoa, aviso de duração.
- Stories com aprovação e exportação `STORY_001.mp4`, `STORY_002.mp4`…
- Timeline segue o frame rate do material e avisa quando há taxas diferentes.
- Exportação 4K, cancelamento, tela sempre ligada durante a exportação.
- Ícone do app e geração automática do IPA.

## Testado de verdade
Com Swift 6.0.3 em Linux:
- `DirectorPlanningCore: 12 checks passed`
- `TimelineCore: 11 checks passed`
- `5 testes de AudioDuckingPlanner passaram.`
- Análise de sintaxe de todos os arquivos Swift sem erro.

## Ainda NÃO comprovado
- Compilação no Xcode. A primeira prova real é o processo do GitHub Actions.
- Prévia, exportação, importação e transcrição em aparelho real.

## Ainda NÃO existe (ver especificação)
- IA de linguagem local: o Diretor segue regras fixas, não entende comando livre.
- Transcrição offline garantida: depende do reconhecimento do iOS estar disponível para pt-BR no aparelho.
- Tela de aprovação de corte de fala com transcrição. Hoje a IA nunca corta fala.
- Análise de conteúdo de vídeo e som, diarização, trilha e SFX automáticos.
- Color Studio, LUTs, transições, proxies, keyframes de texto, tracking robusto.
- Paridade total: na prévia, as animações de texto ainda não aparecem, só na exportação.
