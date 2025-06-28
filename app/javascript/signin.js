// jQueryはapplication.jsでグローバル化済みなので、importは不要
document.addEventListener("DOMContentLoaded", () => {
  if (location.hash) {
    document.querySelector('#hashbang').value = location.hash;
  }
});