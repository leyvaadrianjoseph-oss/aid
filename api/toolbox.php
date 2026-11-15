<?php
require __DIR__ . '/_bootstrap.php';
method_is('GET');
$me = require_user();
[$list, $done] = lessons_for($me['id']);
$titles = [];
foreach ($list as $l) $titles[(int)$l['id']] = $l['title'];

$topics = sb('GET', '/toolbox_topics?order=category.asc,title.asc&select=*');
$out = [];
foreach ($topics as $t) {
    $need = $t['unlock_lesson_id'] === null ? null : (int)$t['unlock_lesson_id'];
    $unlocked = $need === null || isset($done[$need]);
    $row = [
        'id' => (int)$t['id'], 'title' => $t['title'],
        'category' => $t['category'] ?? 'Basics',
        'difficulty' => $t['difficulty'] ?? 'Beginner',
        'tags' => $t['tags'] ?? [],
        'unlocked' => $unlocked,
        'unlock_lesson_id' => $need,
    ];
    if ($unlocked) {
        $row['summary'] = $t['summary'];
        $row['example_code'] = $t['example_code'];
        $row['syntax'] = $t['syntax'] ?? null;
        $row['common_errors'] = $t['common_errors'] ?? [];
    } else {
        $row['unlock_hint'] = 'Finish the level "' . ($titles[$need] ?? 'a later level') . '" to unlock this.';
    }
    $out[] = $row;
}
json_out(['topics' => $out]);
?>