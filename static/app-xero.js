(function () {
  function updateXeroImportFilter(input) {
    var root = input.closest('.modal-content') || document;
    var query = (input.value || '').trim().toLowerCase();
    root.querySelectorAll('[data-xero-import-candidate]').forEach(function (row) {
      var haystack = row.getAttribute('data-xero-import-candidate') || '';
      row.hidden = query !== '' && haystack.indexOf(query) === -1;
    });
  }

  document.addEventListener('input', function (event) {
    var input = event.target.closest('[data-xero-import-search]');
    if (!input) return;
    updateXeroImportFilter(input);
  });

  document.addEventListener('htmx:afterSwap', function (event) {
    var target = event.target;
    if (!target || !target.querySelectorAll) return;
    target.querySelectorAll('[data-xero-import-search]').forEach(updateXeroImportFilter);
  });
})();
