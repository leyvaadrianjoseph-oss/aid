/* Toolbox: searchable, filterable Python reference with copy and practice actions. */
(function () {
  'use strict';
  const PG = window.PG;
  const list = document.getElementById('topics');
  if (!list) return;
  const search = document.getElementById('search');
  const count = document.getElementById('topic-count');
  const category = document.getElementById('category-filter');
  const difficulty = document.getElementById('difficulty-filter');
  let topics = [];

  function button(label, cls, action) {
    const b = PG.el('button', 'px-btn px-btn--small ' + (cls || ''), label);
    b.type = 'button';
    b.addEventListener('click', action);
    return b;
  }

  function render() {
    const term = search.value.trim().toLowerCase();
    const selectedCategory = category.value;
    const selectedDifficulty = difficulty.value;
    list.textContent = '';
    const shown = topics.filter((t) => {
      if (selectedCategory && t.category !== selectedCategory) return false;
      if (selectedDifficulty && t.difficulty !== selectedDifficulty) return false;
      if (!term) return true;
      const hay = [t.title, t.category, t.difficulty, ...(t.tags || []),
        t.unlocked ? t.summary : '', t.unlocked ? t.example_code : '',
        t.unlocked ? t.syntax : '', ...(t.unlocked ? (t.common_errors || []) : [])].join(' ').toLowerCase();
      return hay.includes(term);
    });
    shown.forEach((t) => {
      const card = PG.el('article', 'px-card topic' + (t.unlocked ? '' : ' is-locked'));
      const top = PG.el('div', 'topic__top');
      const heading = PG.el('div');
      heading.appendChild(PG.el('p', 'topic__category', t.category || 'Basics'));
      heading.appendChild(PG.el('h2', null, t.title));
      top.appendChild(heading);
      top.appendChild(PG.el('span', 'topic__difficulty', t.difficulty || 'Beginner'));
      card.appendChild(top);
      if (t.unlocked) {
        card.appendChild(PG.el('p', 'topic__summary', t.summary || ''));
        if (t.syntax) {
          card.appendChild(PG.el('h3', 'topic__label', 'Syntax'));
          card.appendChild(PG.el('pre', 'topic__syntax', t.syntax));
        }
        if (t.example_code) {
          const codeHead = PG.el('div', 'topic__code-head');
          codeHead.appendChild(PG.el('h3', 'topic__label', 'Example'));
          codeHead.appendChild(button('Copy code', 'px-btn--ghost', async () => {
            try {
              await navigator.clipboard.writeText(t.example_code);
              PG.toast('Example copied.');
            } catch (e) {
              const field = PG.el('textarea');
              field.value = t.example_code;
              document.body.appendChild(field);
              field.select();
              const copied = document.execCommand('copy');
              field.remove();
              PG.toast(copied ? 'Example copied.' : 'Copy was blocked by your browser.', !copied);
            }
          }));
          card.appendChild(codeHead);
          const pre = PG.el('pre', 'topic__example');
          pre.appendChild(PG.el('code', null, t.example_code));
          pre.tabIndex = 0;
          pre.setAttribute('aria-label', 'Example code for ' + t.title);
          card.appendChild(pre);
        }
        if (Array.isArray(t.common_errors) && t.common_errors.length) {
          card.appendChild(PG.el('h3', 'topic__label', 'Common mistakes'));
          const errors = PG.el('ul', 'topic__errors');
          t.common_errors.forEach((error) => errors.appendChild(PG.el('li', null, error)));
          card.appendChild(errors);
        }
        if (t.unlock_lesson_id) {
          const actions = PG.el('div', 'topic__actions');
          const practice = PG.el('a', 'px-btn px-btn--sun px-btn--small', 'Practice this topic');
          practice.href = '/level.html?id=' + encodeURIComponent(t.unlock_lesson_id);
          actions.appendChild(practice);
          card.appendChild(actions);
        }
      } else {
        card.appendChild(PG.el('span', 'px-chip px-chip--locked', 'Locked'));
        card.appendChild(PG.el('p', 'muted', t.unlock_hint || 'Complete more Adventure lessons to unlock this topic.'));
      }
      list.appendChild(card);
    });
    count.textContent = shown.length === 0
      ? 'No topics match your filters.'
      : shown.length + ' of ' + topics.length + ' topics shown';
  }

  function populateCategories() {
    const values = Array.from(new Set(topics.map((t) => t.category || 'Basics'))).sort();
    values.forEach((value) => category.appendChild(PG.el('option', null, value)));
  }

  search.addEventListener('input', render);
  category.addEventListener('change', render);
  difficulty.addEventListener('change', render);
  PG.ready.then((me) => {
    if (!me) return;
    PG.api('/api/toolbox.php').then((d) => {
      topics = Array.isArray(d.topics) ? d.topics : [];
      populateCategories();
      render();
    }).catch((e) => PG.toast(e.message, true));
  });
})();