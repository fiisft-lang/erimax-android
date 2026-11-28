(function () {
  'use strict';

  const logoSvg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 430 145" role="img" aria-label="ERIMAX Produtos para Saúde"><rect width="430" height="145" fill="none"/><text x="4" y="99" fill="#F28B00" font-family="Arial,Helvetica,sans-serif" font-size="100" font-weight="900" letter-spacing="-6">ERIMA<tspan dx="14" fill="#1677C8">X</tspan></text><text x="8" y="137" fill="#858585" font-family="Arial,Helvetica,sans-serif" font-size="20" font-weight="800" letter-spacing=".25">PRODUTOS PARA SAÚDE</text></svg>';
  const logoUrl = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(logoSvg);

  function mostrarErroLogin(mensagem) {
    const area = document.getElementById('lgErro');
    if (area) area.textContent = mensagem;
  }

  function iniciarCorrecoesLogin() {
    document.querySelectorAll('#login img.logo, header img.logo').forEach(function (img) {
      img.src = logoUrl;
      img.alt = 'EriMax — Produtos para Saúde';
      img.style.display = 'block';
    });

    const botao = document.querySelector('#login .btn-submit');
    if (botao) {
      botao.type = 'button';
      botao.onclick = function (event) {
        event.preventDefault();
        if (typeof window.entrar !== 'function') {
          mostrarErroLogin('O módulo de login não carregou corretamente. Atualize a página e tente novamente.');
          console.error('[EriMax] A função entrar() não foi carregada.');
          return;
        }
        Promise.resolve(window.entrar()).catch(function (error) {
          console.error('[EriMax] Falha ao executar o login:', error);
          mostrarErroLogin('Não foi possível iniciar o login. Verifique a conexão e tente novamente.');
        });
      };
    }

    const email = document.getElementById('lgEmail');
    if (email) email.addEventListener('keydown', function (event) {
      if (event.key === 'Enter' && botao) botao.click();
    });
  }

  function tratarVoltarAndroid() {
    if (document.body && document.body.classList.contains('menu-lateral-aberto') &&
        typeof window.fecharMenuLateral === 'function') {
      window.fecharMenuLateral();
      return;
    }
    if (typeof window.voltarSistema === 'function') {
      window.voltarSistema();
      return;
    }
    if (window.history.length > 1) window.history.back();
  }

  window.addEventListener('erimaxandroidback', tratarVoltarAndroid);

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', iniciarCorrecoesLogin, { once: true });
  } else {
    iniciarCorrecoesLogin();
  }
})();
