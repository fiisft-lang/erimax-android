(function () {
  'use strict';

  // Mantém a identidade visual original do EriMax mesmo se o WebView
  // aplicar o estilo azul de fallback da tela de login.
  function preservarVisualLogin() {
    if (document.getElementById('erimax-login-visual-fix')) return;

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
      #login .box {
        background:rgba(255,255,255,.94) !important;
        border:1px solid rgba(255,255,255,.9) !important;
        border-top:4px solid var(--secondary,#f28b38) !important;
        border-radius:22px !important;
        box-shadow:0 24px 70px rgba(38,75,110,.16),0 3px 12px rgba(38,75,110,.055) !important;
        backdrop-filter:blur(16px);
      }
      #login .box img.logo {
        display:block !important;
        visibility:visible !important;
        opacity:1 !important;
        max-width:240px !important;
        width:78% !important;
        max-height:90px !important;
        height:auto !important;
        object-fit:contain !important;
      }
    `;
    (document.head || document.documentElement).appendChild(style);
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
    document.addEventListener('DOMContentLoaded', preservarVisualLogin, { once: true });
  } else {
    preservarVisualLogin();
  }
})();
