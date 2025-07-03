document.addEventListener('DOMContentLoaded', () => {

    // Seleciona todos os botões de comprar
    const botoesComprar = document.querySelectorAll('.btn-comprar');

    // Número de WhatsApp para onde a mensagem será enviada
    const numeroWhatsApp = '55SEUNUMERO'; // <-- COLOQUE SEU NÚMERO AQUI

    botoesComprar.forEach(botao => {
        botao.addEventListener('click', () => {
            // Pega as informações do produto do próprio botão usando atributos 'data-'
            const nomeProduto = botao.getAttribute('data-produto');
            const precoProduto = botao.getAttribute('data-preco');

            // Formata a mensagem que será enviada
            const mensagem = `Olá, NUTRI UP! Tenho interesse no produto: *${nomeProduto}* - Preço: *R$ ${precoProduto}*. Gostaria de finalizar a compra.`;
            
            // Codifica a mensagem para ser usada em uma URL
            const mensagemCodificada = encodeURIComponent(mensagem);

            // Cria o link do WhatsApp
            const linkWhatsApp = `https://api.whatsapp.com/send?phone=${numeroWhatsApp}&text=${mensagemCodificada}`;

            // Abre o link em uma nova aba
            window.open(linkWhatsApp, '_blank');
        });
    });

});