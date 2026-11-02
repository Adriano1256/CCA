# Como instalar o Editor IA no iPhone

Um app de iPhone só pode ser compilado em um Mac. Como você usa Windows, o GitHub compila em um Mac na nuvem e entrega o arquivo `EditorIA.ipa`. O Sideloadly instala esse arquivo pelo cabo USB.

## 1. Gerar o IPA

1. Crie um repositório vazio e privado no GitHub chamado `editor-ia-studio`.
2. Envie este projeto para a branch `main`. Isso inicia o processo "Gerar app para iPhone" na aba **Actions**, que leva alguns minutos.
3. Ao terminar, baixe o `EditorIA.ipa` na página **Releases** do repositório.

Se o processo ficar vermelho, o erro está no arquivo `build-device.log`, dentro do resultado do processo.

Custo: em repositório privado, o plano gratuito dá 2.000 minutos por mês e cada minuto de Mac consome 10. São cerca de 200 minutos reais de Mac por mês. Em repositório público é grátis.

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
