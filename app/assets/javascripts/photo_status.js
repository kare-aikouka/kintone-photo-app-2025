(function () {
  function initializePhotoStatusDialog() {
    const dialog = document.querySelector('.js-photo-status-dialog');
    if (!dialog || dialog.dataset.initialized) return;
    dialog.dataset.initialized = 'true';
    const form = dialog.querySelector('.js-photo-status-form');
    const title = dialog.querySelector('h2');
    let submitting = false;

    document.querySelectorAll('.js-photo-status-switch').forEach(function (button) {
      button.addEventListener('click', function () {
        if (submitting) return;
        form.action = button.dataset.updateUrl;
        title.textContent = button.dataset.currentStatus === '完了' ? '写真フラグを完了から未完了に切り替えますか？' : '写真フラグを未完了から完了に切り替えますか？';
        dialog.showModal();
      });
    });

    dialog.querySelector('.js-photo-status-dialog-close').addEventListener('click', function () {
      if (!submitting) dialog.close();
    });
    dialog.addEventListener('cancel', function (event) {
      if (submitting) event.preventDefault();
    });
    form.addEventListener('submit', function (event) {
      if (submitting) {
        event.preventDefault();
        return;
      }
      submitting = true;
      form.setAttribute('aria-busy', 'true');
      dialog.querySelector('.js-photo-status-dialog-close').disabled = true;
    });

    window.addEventListener('pageshow', function () {
      submitting = false;
      form.removeAttribute('aria-busy');
      dialog.querySelector('.js-photo-status-dialog-close').disabled = false;
    });
    document.addEventListener('turbo:before-cache', function () {
      dialog.close();
      delete dialog.dataset.initialized;
    }, { once: true });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', initializePhotoStatusDialog, { once: true });
  else initializePhotoStatusDialog();
  document.addEventListener('turbo:load', initializePhotoStatusDialog);
})();
