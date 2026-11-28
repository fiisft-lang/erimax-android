(function () {
  'use strict';

  const logoSvg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 430 145" role="img" aria-label="ERIMAX Produtos para Saúde"><rect width="430" height="145" fill="none"/><text x="4" y="99" fill="#F28B00" font-family="Arial,Helvetica,sans-serif" font-size="100" font-weight="900" letter-spacing="-6">ERIMA<tspan dx="14" fill="#1677C8">X</tspan></text><text x="8" y="137" fill="#858585" font-family="Arial,Helvetica,sans-serif" font-size="20" font-weight="800" letter-spacing=".25">PRODUTOS PARA SAÚDE</text></svg>';
  const logoUrl = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(logoSvg);

  function iniciarCorrecoesLogin() {
    if (!document.getElementById('erimax-login-visual-fix')) {
      const style = document.createElement('style');
      style.id = 'erimax-login-visual-fix';
      style.textContent = `
        #login {
          background:
            radial-gradient(ellipse at 12% 18%,rgba(71,143,196,.17),transparent 38%),
            radial-gradient(ellipse at 88% 82%,rgba(242,139,56,.13),transparent 34%),
            linear-gradient(135deg,#eaf2f9 0%,#f5f8fc 52%,#fff5eb 100%) !important;
          isolation:isolate !important;
        }
        #login::before { opacity:.22 !important; }
        #login .box {
          background:rgba(255,255,255,.97) !important;
          border:1px solid rgba(255,255,255,.9) !important;
          border-top:4px solid #f28b38 !important;
          border-radius:22px !important;
          box-shadow:0 24px 70px rgba(38,75,110,.16),0 3px 12px rgba(38,75,110,.055) !important;
          backdrop-filter:blur(16px);
        }
        #login .box img.logo {
          display:block !important;
          visibility:visible !important;
          opacity:1 !important;
          width:78% !important;
          max-width:240px !important;
          max-height:90px !important;
          height:auto !important;
          object-fit:contain !important;
          margin:0 auto 18px !important;
        }
      `;
      (document.head || document.documentElement).appendChild(style);
    }

    document.querySelectorAll('#login img.logo, header img.logo').forEach(function (img) {
      if (!img.getAttribute('src') || img.naturalWidth === 0) img.src = logoUrl;
      img.alt = 'EriMax — Produtos para Saúde';
      img.style.visibility = 'visible';
      img.style.opacity = '1';
    });

    const botao = document.querySelector('#login .btn-submit');
    if (botao) {
      botao.type = 'button';
      botao.onclick = function (event) {
        event.preventDefault();
        const loginFn = window.entrar || (typeof entrar === 'function' ? entrar : null);
        if (!loginFn) {
          const area = document.getElementById('lgErro');
          if (area) area.textContent = 'O módulo de login não carregou. Atualize a página e tente novamente.';
          console.error('[EriMax] A função entrar() não está disponível.');
          return;
        }
        Promise.resolve().then(function () { return loginFn(); }).catch(function (error) {
          console.error('[EriMax] Falha ao executar o login:', error);
          const area = document.getElementById('lgErro');
          if (area) area.textContent = 'Não foi possível iniciar o login. Verifique a conexão e tente novamente.';
        });
      };
    }

    const email = document.getElementById('lgEmail');
    if (email && !email.dataset.erimaxEnterBound) {
      email.dataset.erimaxEnterBound = '1';
      email.addEventListener('keydown', function (event) {
        if (event.key === 'Enter' && botao) botao.click();
      });
    }
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
