(function () {
  function initializeSiteMap() {
    const root = document.querySelector('.js-site-map');
    if (!root || root.dataset.initialized) return;
    root.dataset.initialized = 'true';

    const status = root.querySelector('.js-site-map-status');
    if (!window.L) {
      status.textContent = '地図を読み込めませんでした。通信状況を確認して画面を更新してください。';
      return;
    }

    const canvas = root.querySelector('.js-site-map-canvas');
    const navigate = root.querySelector('.js-site-map-navigate');
    const save = root.querySelector('.js-site-map-save');
    const saveStatus = root.querySelector('.js-site-map-save-status');
    const form = root.querySelector('.js-site-map-search');
    const input = form.querySelector('input');
    const searchButton = form.querySelector('button');
    const latitude = Number(root.dataset.lat);
    const longitude = Number(root.dataset.lng);
    const hasStoredPoint = root.dataset.lat && root.dataset.lng && Number.isFinite(latitude) && Number.isFinite(longitude);
    const map = L.map(canvas).setView(hasStoredPoint ? [latitude, longitude] : [38, 138], hasStoredPoint ? 17 : 5);
    let searchController = null;
    let hasPoint = Boolean(hasStoredPoint);
    let saving = false;
    let savedPointKey = hasStoredPoint ? pointKey({ lat: latitude, lng: longitude }) : null;

    function pointKey(point) {
      return point.lat.toFixed(7) + ',' + point.lng.toFixed(7);
    }

    function updateActions() {
      navigate.disabled = !hasPoint || saving;
      save.disabled = !hasPoint || saving || savedPointKey === pointKey(map.getCenter());
      searchButton.disabled = saving || Boolean(searchController);
    }

    L.tileLayer('https://cyberjapandata.gsi.go.jp/xyz/std/{z}/{x}/{y}.png', {
      minZoom: 5,
      maxNativeZoom: 18,
      maxZoom: 20,
      attribution: '<a href="https://maps.gsi.go.jp/development/ichiran.html" target="_blank" rel="noopener noreferrer">国土地理院</a>'
    }).addTo(map).on('tileerror', function () {
      status.textContent = '地図画像を読み込めません。通信状況を確認してください。';
    });

    function cancelSearch() {
      if (searchController) searchController.abort();
      searchController = null;
      searchButton.disabled = false;
    }

    function selectPoint() {
      cancelSearch();
      hasPoint = true;
      updateActions();
      if (!saving) saveStatus.textContent = '';
      status.textContent = '選択した位置を確認して「この場所へナビ」を押してください。';
    }

    map.on('dragend', selectPoint);
    map.on('moveend', function () {
      if (!hasPoint) return;
      updateActions();
      if (!saving && savedPointKey !== pointKey(map.getCenter())) saveStatus.textContent = '';
    });
    map.on('click', function (event) {
      map.panTo(event.latlng, { animate: false });
      selectPoint();
    });

    async function searchAddress(address) {
      if (saving) return;
      cancelSearch();
      const controller = new AbortController();
      searchController = controller;
      const timeout = window.setTimeout(function () { controller.abort(); }, 15000);
      searchButton.disabled = true;
      hasPoint = false;
      updateActions();
      saveStatus.textContent = '';
      status.textContent = '住所から参考位置を検索中…';
      try {
        const url = new URL(root.dataset.searchUrl, window.location.origin);
        url.searchParams.set('address', address);
        const response = await fetch(url, { headers: { Accept: 'application/json' }, signal: controller.signal });
        if (response.redirected) throw new Error('ログイン状態を確認し、画面を開き直してください。');
        const result = await response.json();
        if (controller !== searchController) return;
        if (!response.ok) throw new Error(result.message || '住所を検索できませんでした。');
        if (!Number.isFinite(result.lat) || !Number.isFinite(result.lng)) throw new Error('位置を取得できませんでした。');
        map.setView([result.lat, result.lng], 16);
        hasPoint = true;
        updateActions();
        status.textContent = '参考位置：' + (result.label || address) + '。正確な現場の位置を確認してください。';
      } catch (error) {
        if (controller !== searchController) return;
        status.textContent = error.name === 'AbortError' ? '検索がタイムアウトしました。再検索するか、地図で現場を選んでください。' : error.message;
      } finally {
        window.clearTimeout(timeout);
        if (controller === searchController) {
          searchController = null;
          searchButton.disabled = false;
        }
      }
    }

    form.addEventListener('submit', function (event) {
      event.preventDefault();
      if (input.value.trim()) searchAddress(input.value.trim());
    });

    save.addEventListener('click', async function () {
      if (!hasPoint || saving || !window.confirm('中央のピンの位置を、この物件のB地点緯度・B地点経度に保存します。よろしいですか？')) return;
      const point = map.getCenter();
      const controller = new AbortController();
      const timeout = window.setTimeout(function () { controller.abort(); }, 25000);
      saving = true;
      updateActions();
      save.textContent = '保存中…';
      saveStatus.textContent = '現場の位置を保存しています…';
      try {
        const token = document.querySelector('meta[name="csrf-token"]');
        const response = await fetch(root.dataset.saveUrl, {
          method: 'PATCH',
          credentials: 'same-origin',
          headers: { 'Content-Type': 'application/json', Accept: 'application/json', 'X-CSRF-Token': token ? token.content : '' },
          body: JSON.stringify({ lat: point.lat.toFixed(7), lng: point.lng.toFixed(7) }),
          signal: controller.signal
        });
        if (response.redirected) throw new Error('ログイン状態を確認し、画面を開き直してB地点を確認してください。');
        const result = await response.json();
        if (!response.ok || result.status !== 'success') throw new Error(result.message || '保存結果を確認できませんでした。画面を開き直してB地点を確認してください。');
        savedPointKey = pointKey(point);
        saveStatus.textContent = savedPointKey === pointKey(map.getCenter()) ? result.message : '確定時の位置を保存しました。現在選択している位置は未保存です。';
      } catch (error) {
        saveStatus.textContent = error.name === 'AbortError' || error instanceof TypeError || error instanceof SyntaxError ? '保存結果を確認できませんでした。通信状況を確認し、画面を開き直してB地点を確認してください。' : error.message;
      } finally {
        window.clearTimeout(timeout);
        saving = false;
        save.textContent = 'この位置を保存';
        updateActions();
      }
    });

    navigate.addEventListener('click', function () {
      if (!hasPoint || saving || !window.confirm('中央のピンの位置を目的地にしてGoogleマップを開きます。よろしいですか？')) return;
      const point = map.getCenter();
      const url = new URL('https://www.google.com/maps/dir/');
      url.searchParams.set('api', '1');
      url.searchParams.set('destination', point.lat.toFixed(7) + ',' + point.lng.toFixed(7));
      url.searchParams.set('travelmode', 'driving');
      url.searchParams.set('dir_action', 'navigate');
      window.open(url.toString(), '_blank', 'noopener,noreferrer');
    });

    if (hasStoredPoint) {
      updateActions();
      status.textContent = 'kintoneのB地点を表示しています。現場の位置を確認してください。';
    } else if (root.dataset.address) {
      searchAddress(root.dataset.address);
    } else {
      status.textContent = '住所を検索するか、地図で現場を選んでください。';
    }

    window.addEventListener('resize', function () { map.invalidateSize(); });
    document.addEventListener('turbo:before-cache', function () {
      cancelSearch();
      map.remove();
      delete root.dataset.initialized;
    }, { once: true });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', initializeSiteMap, { once: true });
  else initializeSiteMap();
  document.addEventListener('turbo:load', initializeSiteMap);
})();
