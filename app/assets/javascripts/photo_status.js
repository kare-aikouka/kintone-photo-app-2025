(function () {
  function initializePhotoStatusDialog() {
    const dialog = document.querySelector('.js-photo-status-dialog');
    if (!dialog || dialog.dataset.initialized) return;
    dialog.dataset.initialized = 'true';
    const form = dialog.querySelector('.js-photo-status-form');
    const title = dialog.querySelector('h2');
    const submit = form.querySelector('button[type="submit"]');
    const back = form.querySelector('.photo-status-dialog-back');
    let submitting = false;

    document.querySelectorAll('.js-photo-status-switch').forEach(function (button) {
      button.addEventListener('click', function () {
        if (submitting) return;
        form.action = button.dataset.updateUrl;
        const restoring = button.dataset.visibilityAction === 'show';
        title.textContent = restoring ? 'この物件を通常の一覧に戻しますか？' : 'この物件をアプリの一覧から非表示にしますか？';
        submit.value = restoring ? 'show' : 'hide';
        submit.textContent = restoring ? '一覧に戻す' : '一覧から非表示にする';
        dialog.showModal();
      });
    });

    dialog.querySelector('.js-photo-status-dialog-close').addEventListener('click', function () {
      if (!submitting) dialog.close();
    });
    back.addEventListener('click', function () {
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
      back.disabled = true;
    });

    window.addEventListener('pageshow', function () {
      submitting = false;
      form.removeAttribute('aria-busy');
      dialog.querySelector('.js-photo-status-dialog-close').disabled = false;
      back.disabled = false;
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
