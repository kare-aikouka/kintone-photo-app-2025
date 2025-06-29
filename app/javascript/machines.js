document.addEventListener('DOMContentLoaded', function () {
  const btnHokkaido = document.getElementById('btn-hokkaido');
  const btnHonshu = document.getElementById('btn-honshu');
  const companyListDiv = document.getElementById('company-list');
  let area = "北海道"; // 初期値

  // グループ化+ソート
  function groupAndSort(data, areaName) {
    // areaNameでフィルタ
    const areaRows = data.filter(row => row["エリア"]?.value === areaName);

    // 運用会社でグループ化
    const companyMap = {};
    areaRows.forEach(row => {
      const corpName = row["運用会社名"]?.value || "未設定";
      const corpOrder = Number(row["運用会社並び順"]?.value || 9999);
      const machName = row["施工班通称"]?.value || "";
      const machOrder = Number(row["施工機並び順"]?.value || 9999);

      console.log("[DEBUG]", corpName, machName, machOrder);

      if (!companyMap[corpName]) {
        companyMap[corpName] = {
          corpOrder: corpOrder,
          machines: []
        };
      }
      if (machName) {
        companyMap[corpName].machines.push({ machName, machOrder });
      }
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
    companies.forEach(({ corpName, machines }) => {
      html += `<div class="corp-name" style="margin:8px 0;cursor:pointer;font-weight:bold;" tabindex="0" onclick="this.nextElementSibling.classList.toggle('hidden')">${corpName}</div>`;
      if (machines.length > 0) {
        html += `<ul class="hidden" style="margin:0 0 8px 24px;padding:0;">`;
        machines.forEach(({ machName }) => {
          html += `<li>${machName}</li>`;
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
