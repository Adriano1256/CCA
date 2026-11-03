# Como instalar o Editor IA no iPhone

Um app de iPhone só pode ser compilado em um Mac. Como você usa Windows, o GitHub compila em um Mac na nuvem e entrega o arquivo `EditorIA.ipa`. O Sideloadly instala esse arquivo pelo cabo USB.

## 1. Baixar o IPA

O arquivo é gerado sozinho na nuvem a cada atualização. Baixe sempre o mais novo em:

https://github.com/Adriano1256/CCA/releases/latest

Clique em `EditorIA.ipa` para baixar.

## 2. Preparar o PC (uma vez só)

1. Instale o **iTunes** e o **iCloud baixados do site da Apple**, não da Microsoft Store. Se tiver a versão da Store, desinstale antes.
2. Instale o **Sideloadly** pelo site oficial (sideloadly.io).

## 3. Instalar

1. Ligue o iPhone no PC pelo cabo e toque em **Confiar** no iPhone.
2. Abra o Sideloadly. O iPhone deve aparecer em **iDevice**.
3. Clique no ícone de IPA e escolha o `EditorIA.ipa`.
4. Digite seu Apple ID e clique em **Start**. Digite a senha e o código de verificação.
5. No iPhone, abra **Ajustes > Privacidade e Segurança > Modo Desenvolvedor**, ative e reinicie.
6. Em **Ajustes > Geral > VPN e Gerenciamento de Dispositivo**, toque no seu Apple ID e em **Confiar**.

Se travar na assinatura: feche o iTunes por completo e renomeie a pasta `C:\ProgramData\Apple Computer\iTunes\adi`. Depois tente de novo.

## Limites do Apple ID gratuito

- O app **para de abrir depois de 7 dias** e precisa ser renovado. Com o Sideloadly aberto, o iPhone conectado e os dois na mesma rede Wi-Fi, a renovação pode ser automática (ícone de atualizar à esquerda do Start). Seus projetos ficam guardados se você reinstalar por cima, sem apagar o app.
- No máximo **3 apps** instalados assim por conta.
- Para acabar com o limite de 7 dias e instalar pelo TestFlight, sem PC: conta Apple Developer, paga por ano.

## Depois de instalar

Os vídeos exportados ficam no botão de exportar (Compartilhar ou Salvar na Fototeca) e no app **Arquivos**, em Neste iPhone > Editor IA.

## Primeiro uso

1. Abra o app e toque em **+** para importar os vídeos (Arquivos ou Fototeca), na ordem em que foram gravados.
2. O app analisa o material sozinho: fala, música, batidas e transcrição.
3. Abra a aba **Chat** e peça. Exemplos: "edita no padrão do Breu Branco", "deixa 15 segundos de B-roll antes da primeira fala", "legenda estilo MrBeast", "tira o som do B-roll e coloca legenda neon".
4. Para pedidos livres, baixe um modelo de IA uma vez, com Wi-Fi: Chat > Modelos. No iPhone 17 Pro Max o recomendado é o Gemma 4 12B. Baixe também o Whisper para transcrever em português.
5. Exporte pelo botão de compartilhar, escolhendo qualidade, resolução e quadros por segundo.

## O que ainda não foi testado no iPhone de verdade

Tudo foi testado na nuvem, em simulador, mas não em um iPhone real: a velocidade da IA, o Gemma 4 12B, o Whisper e a exportação com a placa de vídeo do aparelho. Se algo falhar, me conte o que apareceu na tela.
