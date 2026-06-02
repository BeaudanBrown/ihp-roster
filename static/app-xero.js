(function () {
  function fuzzyIncludes(haystack, query) {
    if (!query) return true;
    if (haystack.indexOf(query) !== -1) return true;

    var haystackIndex = 0;
    for (var queryIndex = 0; queryIndex < query.length; queryIndex += 1) {
      var character = query.charAt(queryIndex);
      haystackIndex = haystack.indexOf(character, haystackIndex);
      if (haystackIndex === -1) return false;
      haystackIndex += 1;
    }
    return true;
  }

  function updateXeroImportFilter(input) {
    var root = input.closest('.modal-content') || document;
    var query = (input.value || '').trim().toLowerCase();
    root.querySelectorAll('[data-xero-import-candidate]').forEach(function (row) {
      var haystack = row.getAttribute('data-xero-import-candidate') || '';
      var matches = fuzzyIncludes(haystack, query);
      row.hidden = !matches;
      row.classList.toggle('d-none', !matches);
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
