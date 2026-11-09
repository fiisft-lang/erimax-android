// Atualização remota limitada ao canal nativo compatível do EriMax.
(function(){
  const RAW_BASE = 'https://raw.githubusercontent.com/fiisft-lang/erimax-android/';
  const PENDING_KEY = 'erimax_ota_pending_bundle';
  const PLUGIN = () => window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.LiveUpdate;
  const isAndroid = () => !!(window.Capacitor && typeof window.Capacitor.getPlatform === 'function' && window.Capacitor.getPlatform() === 'android');
  let readyPromise = null;
  let checking = false;

  function storageGet(key){
    try { return localStorage.getItem(key); } catch (_) { return null; }
  }
  function storageSet(key,value){
    try { localStorage.setItem(key,value); } catch (_) {}
  }
  function storageRemove(key){
    try { localStorage.removeItem(key); } catch (_) {}
  }

  async function ready(){
    const live = PLUGIN();
    if(!isAndroid() || !live || typeof live.ready !== 'function') return null;
    if(!readyPromise) readyPromise = live.ready().catch(error => {
      console.warn('[EriMax OTA] Não foi possível confirmar a inicialização:', error);
      return null;
    });
    const result = await readyPromise;
    // Confirma ao usuário se o pacote que foi selecionado realmente entrou em uso.
    const expected = storageGet(PENDING_KEY);
    if(expected){
      let current = null;
      try { current = await live.getCurrentBundle(); } catch (_) {}
      const currentId = current && current.bundleId || 'padrão do APK';
      if(current && current.bundleId === expected){
        storageRemove(PENDING_KEY);
        setTimeout(()=>alert('Atualização do EriMax aplicada com sucesso.\nPacote: '+expected.slice(0,12)),700);
      } else {
        const rollback = !!(result && result.rollback);
        setTimeout(()=>alert('A atualização do EriMax não foi confirmada.\nPacote esperado: '+expected.slice(0,12)+'\nPacote em uso: '+currentId+'\n'+(rollback?'O sistema voltou ao pacote anterior por segurança.':'O pacote novo ainda não está ativo.')),700);
      }
    }
    return result;
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
      const branch = channel === 'staging' ? 'ota-atualizacao-android-staging-20261109' : 'main';
      const manifestUrl = RAW_BASE + branch + '/ota/manifest.json?ts=' + Date.now();
      const response = await fetch(manifestUrl, {cache:'no-store'});
      if(!response.ok) throw new Error('Manifesto de atualização indisponível (' + response.status + '). Canal detectado: ' + channel + '.');
      const manifest = await response.json();
      if(!manifest || typeof manifest.bundleId !== 'string' || !/^[a-zA-Z0-9._-]{1,80}$/.test(manifest.bundleId)) throw new Error('Identificador do pacote de atualização inválido.');
      if(typeof manifest.checksum !== 'string' || !/^[a-f0-9]{64}$/i.test(manifest.checksum)) throw new Error('Verificação de integridade do pacote inválida.');
      const bundleUrl = new URL(manifest.url);
      const allowedPath = '/fiisft-lang/erimax-android/' + branch + '/ota/';
      if(bundleUrl.origin !== 'https://raw.githubusercontent.com' || !bundleUrl.pathname.startsWith(allowedPath)) throw new Error('Endereço do pacote não corresponde ao canal '+channel+'.');
      const localBuildResponse = await fetch('ota-build.json?ts=' + Date.now(), {cache:'no-store'});
      if(localBuildResponse.ok){
        const localBuild = await localBuildResponse.json();
        if(localBuild && localBuild.bundleId === manifest.bundleId) return;
      }
      const current = await live.getCurrentBundle();
      if(current && current.bundleId === manifest.bundleId) return;
      const versionCode = typeof live.getVersionCode === 'function' ? Number((await live.getVersionCode()).versionCode) : 0;
      const minimum = Number(manifest.minimumNativeVersionCode || 1);
      if(versionCode && minimum > versionCode) throw new Error('Esta atualização exige uma versão mais recente do aplicativo Android.');
      await live.downloadBundle({url:bundleUrl.toString(),bundleId:manifest.bundleId,checksum:manifest.checksum});
      await live.setNextBundle({bundleId:manifest.bundleId});
      const next = typeof live.getNextBundle === 'function' ? await live.getNextBundle() : null;
      if(!next || next.bundleId !== manifest.bundleId) throw new Error('O pacote foi baixado, mas o Android não confirmou a seleção para atualização.');
      const notes = typeof manifest.message === 'string' && manifest.message.trim() ? '\n\n' + manifest.message.trim() : '';
      const applyNow = window.confirm('Nova atualização do EriMax disponível!' + notes + '\n\nDeseja atualizar agora? Se estiver preenchendo uma O.S., escolha “Cancelar” e a atualização será aplicada na próxima abertura do aplicativo.');
      if(applyNow){
        storageSet(PENDING_KEY,manifest.bundleId);
        await live.reload();
      }
    }catch(error){
      console.error('[EriMax OTA] Verificação/instalação não concluída:',error);
      alert('Não foi possível concluir a atualização do EriMax.\n\nMotivo: '+(error && error.message ? error.message : String(error))+'\n\nNenhum dado das ordens de serviço foi apagado.');
    }finally{
      checking = false;
    }
  }

  window.erimaxOTA = {ready,checkForUpdate};
  if(document.readyState === 'loading') document.addEventListener('DOMContentLoaded',()=>{ready();},{once:true});
  else ready();
})();