document.addEventListener('DOMContentLoaded', function () {
  const btnHokkaido = document.getElementById('btn-hokkaido');
  const btnHonshu = document.getElementById('btn-honshu');
  const companyListDiv = document.getElementById('company-list');
  let area = "北海道"; // 初期値

  const fieldAliases = {
    area: ["エリア", "地域", "施工エリア"],
    companyName: ["運用会社名", "運用会社", "会社名", "施工会社", "施工会社名", "協力会社", "協力会社名", "業者名"],
    companyOrder: ["運用会社並び順", "会社並び順", "並び順_会社", "会社順"],
    machineName: ["施工班通称", "施工機通称", "施工機名", "施工機", "施工班名", "施工班", "機械名", "重機名"],
    machineOrder: ["施工機並び順", "施工班並び順", "並び順_施工機", "機械並び順", "施工機順"]
  };

  function fieldValue(row, aliases) {
    for (const fieldCode of aliases) {
      const value = row?.[fieldCode]?.value;
      if (value !== undefined && value !== null && String(value).trim() !== "") {
        return value;
      }
    }
    return "";
  }

  function recordId(row) {
    return row?.$id?.value || row?.レコード番号?.value || "";
  }

  function escapeHtml(value) {
    return String(value)
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
  }

  function photosPath(machineName) {
    return `/photos?machine=${encodeURIComponent(machineName)}`;
  }

  // グループ化+ソート
  function groupAndSort(data, areaName) {
    // areaNameでフィルタ
    const areaRows = (data || []).filter(row => fieldValue(row, fieldAliases.area) === areaName);

    // 運用会社でグループ化
    const companyMap = {};
    areaRows.forEach(row => {
      const corpName = fieldValue(row, fieldAliases.companyName) || "会社未設定";
      const corpOrder = Number(fieldValue(row, fieldAliases.companyOrder) || 9999);
      const machName = fieldValue(row, fieldAliases.machineName) || `名称未設定${recordId(row) ? `（レコード${recordId(row)}）` : ""}`;
      const machOrder = Number(fieldValue(row, fieldAliases.machineOrder) || 9999);

      console.log("[DEBUG]", corpName, machName, machOrder);

      if (!companyMap[corpName]) {
        companyMap[corpName] = {
          corpOrder: corpOrder,
          machines: []
        };
      }
      companyMap[corpName].machines.push({ machName, machOrder });
    });

    // 会社と施工機を並び順でソート
    const companyList = Object.entries(companyMap).map(([corpName, { corpOrder, machines }]) => {
      machines.sort((a, b) => a.machOrder - b.machOrder);
      return { corpName, corpOrder, machines };
    }).sort((a, b) => a.corpOrder - b.corpOrder);

    return companyList;
  }

  function renderCompanyList() {
    const companies = groupAndSort(window.machineData, area);
    let html = '';
    if (companies.length === 0) {
      companyListDiv.innerHTML = '<p style="margin-top:16px;color:#888;">該当する施工機レコードがありません。</p>';
      return;
    }
    companies.forEach(({ corpName, machines }) => {
      html += `<div class="corp-name" style="margin:8px 0;cursor:pointer;font-weight:bold;" tabindex="0" onclick="this.nextElementSibling.classList.toggle('hidden')">${corpName}</div>`;
      if (machines.length > 0) {
        html += `<ul style="margin:0 0 8px 24px;padding:0;">`;
        machines.forEach(({ machName }) => {
          html += `<li><a class="machine-name" href="${photosPath(machName)}">${escapeHtml(machName)}</a></li>`;
        });
        html += `</ul>`;
      } else {
        html += `<ul class="hidden" style="margin:0 0 8px 24px;padding:0;"><li style="color:#ccc;">（登録なし）</li></ul>`;
      }
    });
    companyListDiv.innerHTML = html;
  }

  // --- エリア切替 ---
  btnHokkaido.onclick = function () {
    area = "北海道";
    btnHokkaido.classList.add('selected');
    btnHonshu.classList.remove('selected');
    renderCompanyList();
  };
  btnHonshu.onclick = function () {
    area = "本州";
    btnHokkaido.classList.remove('selected');
    btnHonshu.classList.add('selected');
    renderCompanyList();
  };

  // 初期表示
  btnHokkaido.classList.add('selected');
  btnHonshu.classList.remove('selected');
  renderCompanyList();
});
