(function(){
  const PRODUCTION_ORIGIN = 'https://erimax.pages.dev';
  const STAGING_ORIGIN = 'https://ota-atualizacao-android-staging-20261109.erimax.pages.dev';
  const PLUGIN = () => window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.LiveUpdate;
  const isAndroid = () => !!(window.Capacitor && typeof window.Capacitor.getPlatform === 'function' && window.Capacitor.getPlatform() === 'android');
  let readyPromise = null;
  let checking = false;

  async function ready(){
    const live = PLUGIN();
    if(!isAndroid() || !live || typeof live.ready !== 'function') return;
    if(!readyPromise) readyPromise = live.ready().catch(error => {
      console.warn('[EriMax OTA] Não foi possível confirmar a inicialização:', error);
      return null;
    });
    return readyPromise;
  }

  async function checkForUpdate(){
    if(checking || !isAndroid()) return;
    const live = PLUGIN();
    if(!live || typeof live.getCurrentBundle !== 'function') return;
    checking = true;
    try{
      await ready();
      const channelInfo = typeof live.getChannel === 'function' ? await live.getChannel().catch(()=>null) : null;
      const channel = channelInfo && channelInfo.channel === 'staging' ? 'staging' : 'production';
      const origin = channel === 'staging' ? STAGING_ORIGIN : PRODUCTION_ORIGIN;
      const response = await fetch(origin + '/ota/manifest.json?ts=' + Date.now(), {cache:'no-store'});
      if(!response.ok) throw new Error('Manifesto de atualização indisponível (' + response.status + ').');
      const manifest = await response.json();
      if(!manifest || typeof manifest.bundleId !== 'string' || !/^[a-zA-Z0-9._-]{1,80}$/.test(manifest.bundleId)) return;
      if(typeof manifest.checksum !== 'string' || !/^[a-f0-9]{64}$/i.test(manifest.checksum)) return;
      const bundleUrl = new URL(manifest.url, origin);
      if(bundleUrl.origin !== origin || !bundleUrl.pathname.startsWith('/ota/')) return;
      const current = await live.getCurrentBundle();
      if(current && current.bundleId === manifest.bundleId) return;
      const versionCode = typeof live.getVersionCode === 'function' ? Number((await live.getVersionCode()).versionCode) : 0;
      const minimum = Number(manifest.minimumNativeVersionCode || 1);
      if(versionCode && minimum > versionCode) {
        console.info('[EriMax OTA] Atualização exige uma versão nativa mais recente.');
        return;
      }
      await live.downloadBundle({url:bundleUrl.toString(),bundleId:manifest.bundleId,checksum:manifest.checksum});
      await live.setNextBundle({bundleId:manifest.bundleId});
      const notes = typeof manifest.message === 'string' && manifest.message.trim() ? '\n\n' + manifest.message.trim() : '';
      const applyNow = window.confirm('Nova atualização do EriMax disponível!' + notes + '\n\nDeseja atualizar agora? Se estiver preenchendo uma O.S., escolha “Cancelar” e a atualização será aplicada na próxima abertura do aplicativo.');
      if(applyNow) await live.reload();
    }catch(error){
      console.warn('[EriMax OTA] Verificação/instalação não concluída:',error);
    }finally{
      checking = false;
    }
  }

  window.erimaxOTA = {ready,checkForUpdate};
})();
