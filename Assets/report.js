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
