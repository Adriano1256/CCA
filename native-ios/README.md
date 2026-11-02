# Editor IA · Native iOS/iPadOS · v0.24

Aplicativo nativo em SwiftUI com prioridade para iPhone e iPad. O protótipo web é apenas uma bancada de interface e lógica compartilhada; não substitui o app nativo.

## Gerar o projeto Xcode

Requisitos: Mac com Xcode 15 ou superior e XcodeGen.

```bash
brew install xcodegen
xcodegen generate --spec project.yml
open EditorIA.xcodeproj
```

Sem Mac, use o GitHub Actions: veja `INSTALAR_NO_IPHONE.md`.

O projeto gerado usa bundle identifier provisório `com.criativar.editoria`. Antes de instalar em aparelho físico ou publicar, configure seu Team e assinatura no Xcode.

## Incluído
- Navegação adaptável para iPhone/iPad.
- Importação múltipla pela Fototeca com PhotosPicker e por Arquivos.
- Cópia dos originais para Application Support/EditorIA/Media.
- Projeto JSON local e recuperação.
- Timeline multipista com seleção, divisão, duplicação, exclusão, movimentação e ajuste de duração.
- Trim de entrada e saída não destrutivo.
- Histórico de desfazer/refazer.
- Pré-visualização de mídia.
- Primeiro renderizador local AVFoundation para clipes de vídeo e áudio, com composição básica de faixas e sobreposição de imagens sobre vídeo.
- Exportação local MP4 com proporções 16:9, 9:16, 4:5 e 1:1, compartilhamento e opção de salvar na Fototeca.
- Controles de volume, fades de entrada/saída e keyframes de opacidade, escala e volume no renderizador.

## Limitações conhecidas da exportação 0.7
- Ainda não há renderização de projetos compostos somente por imagens.
- Ainda não há transições, textos/legendas renderizados ou animações tipográficas no exportador. Os keyframes atuais controlam opacidade, escala e volume de clipes.
- O posicionamento e a composição de camadas são básicos e precisam de validação visual em aparelho real.
- O Sound Director ainda não faz análise acústica automática nem ducking inteligente.
- O renderizador não substitui um motor NLE completo.

## Compilação
O projeto Xcode é gerado por XcodeGen a partir de `project.yml`. A compilação precisa ocorrer em macOS com Xcode. O ambiente de desenvolvimento atual não inclui Xcode, portanto a validação final em simulador e aparelho ainda está pendente.


### v0.14: person cutout on still images
The Motion Studio can run Vision person segmentation locally on a selected photograph and create a transparent PNG. The generated subject layer is aligned with the original still clip and rendered above text layers. This supports a first text-behind-person composition for photos. Video segmentation and temporal tracking are not included yet.


### v0.19 · Feather de máscaras de vídeo
- O Motion Studio permite ajustar suavização da borda antes da análise.
- `VideoPersonSegmentationService` aplica Gaussian Blur à máscara, com raio limitado.
- `manifest.json` registra o raio usado; manifestos antigos são aceitos com valor 0.
- Requer validação visual em iPhone/iPad: o feather pode reduzir serrilhado, mas valores altos podem criar halos.
