/* ═══════════════════════════════════════════════════════════════════════════
   PurviewAssessment — report.js
   Interactividad compartida de todos los informes. Sin dependencias externas.
   El bootstrap anti-parpadeo del tema se inyecta aparte en <head>
   (ver New-PavHtmlDocument).
   ═══════════════════════════════════════════════════════════════════════════ */

/* Conmutador de tema día/noche con persistencia local */
function pavToggleTheme() {
  var root = document.documentElement;
  var next = (root.getAttribute('data-theme') === 'light') ? 'dark' : 'light';
  root.setAttribute('data-theme', next);
  try { localStorage.setItem('pav-report-theme', next); } catch (e) {}
}

/* Colapsar/expandir una tarjeta */
function pavToggleCard(head) {
  head.parentElement.classList.toggle('exp');
}

/* Expandir/contraer todas las tarjetas del panel visible */
function pavToggleAll() {
  var scope = document.querySelector('.pav-panel.active') || document;
  var cards = scope.querySelectorAll('.pav-card');
  var expand = false;
  for (var i = 0; i < cards.length; i++) {
    if (!cards[i].classList.contains('exp')) { expand = true; break; }
  }
  for (var j = 0; j < cards.length; j++) {
    cards[j].classList.toggle('exp', expand);
  }
}

/* Cambiar de pestaña (informe consolidado) */
function pavSwitchTab(btn, panelId) {
  document.querySelectorAll('.pav-tab').forEach(function (t) { t.classList.remove('active'); });
  document.querySelectorAll('.pav-panel').forEach(function (p) { p.classList.remove('active'); });
  btn.classList.add('active');
  var panel = document.getElementById(panelId);
  if (panel) { panel.classList.add('active'); }
  pavFilter(); /* re-aplica el filtro activo al nuevo panel */
}

/* Búsqueda en vivo sobre tarjetas del panel visible */
function pavFilter() {
  var input = document.getElementById('pav-search');
  if (!input) { return; }
  var q = input.value.toLowerCase();
  var scope = document.querySelector('.pav-panel.active') || document;
  scope.querySelectorAll('.pav-card').forEach(function (c) {
    var name = (c.getAttribute('data-name') || '').toLowerCase();
    var show = q === '' || name.indexOf(q) > -1 || c.textContent.toLowerCase().indexOf(q) > -1;
    c.style.display = show ? '' : 'none';
  });
}

// Filtro por atributo data-*: los botones activos acumulan criterios y se
// combinan con el buscador de texto.
var pavActiveFilters = {};
function pavFilterBy(btn, attr, value) {
  var group = btn.parentNode;
  var was = btn.classList.contains('active');
  var i, b = group.getElementsByClassName('pav-chip');
  for (i = 0; i < b.length; i++) { b[i].classList.remove('active'); }
  if (was) { delete pavActiveFilters[attr]; }
  else { btn.classList.add('active'); pavActiveFilters[attr] = value; }
  pavApplyFilters();
}
function pavApplyFilters() {
  var cards = document.getElementsByClassName('pav-card');
  var q = (document.getElementById('pav-search') || {}).value;
  q = q ? q.toLowerCase() : '';
  for (var i = 0; i < cards.length; i++) {
    var c = cards[i], ok = true;
    for (var a in pavActiveFilters) {
      if (pavActiveFilters.hasOwnProperty(a) && c.getAttribute('data-' + a) !== pavActiveFilters[a]) { ok = false; break; }
    }
    if (ok && q) {
      var n = (c.getAttribute('data-name') || '') + ' ' + c.textContent;
      if (n.toLowerCase().indexOf(q) === -1) { ok = false; }
    }
    c.style.display = ok ? '' : 'none';
  }
}
