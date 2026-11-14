<?php
require __DIR__ . '/_bootstrap.php';
$method = method_is('GET', 'POST');
$me = require_user();
[$list, $done] = lessons_for($me['id']);
$uid = q($me['id']);

if ($method === 'GET') {
    $achievements = sb('GET', '/achievements?order=id.asc&select=*');
    $doneCount = count($done);
    $metrics = ['lessons_done' => $doneCount, 'xp' => (int)$me['xp'], 'streak' => (int)$me['streak']];
    $earnedRows = sb('GET', '/user_achievements?user_id=eq.' . $uid . '&select=achievement_id,earned_at');
    $earnedIds = [];
    foreach ($earnedRows as $row) $earnedIds[(int)$row['achievement_id']] = $row['earned_at'] ?? null;
    foreach ($achievements as &$a) {
        $id = (int)$a['id'];
        $qualifies = ($metrics[$a['rule_key']] ?? 0) >= (int)$a['threshold'];
        if ($qualifies && !array_key_exists($id, $earnedIds)) {
            sb('POST', '/user_achievements?on_conflict=user_id,achievement_id', [
                'user_id' => $me['id'], 'achievement_id' => $id
            ], ['resolution=ignore-duplicates', 'return=minimal']);
            $earnedIds[$id] = gmdate('c');
        }
        $a['earned'] = array_key_exists($id, $earnedIds);
        $a['earned_at'] = $earnedIds[$id] ?? null;
    }
    unset($a);

    $concepts = [];
    foreach ($list as $l) {
        $name = $l['concept'] ?: $l['title'];
        $concepts[$name]['total'] = ($concepts[$name]['total'] ?? 0) + 1;
        $concepts[$name]['done'] = ($concepts[$name]['done'] ?? 0) + ($l['status'] === 'done' ? 1 : 0);
    }
    $mastery = [];
    foreach ($concepts as $name => $c) $mastery[] = ['concept' => $name, 'done' => $c['done'], 'total' => $c['total']];

    $history = sb('GET', '/user_progress?user_id=eq.' . $uid . '&status=eq.done&completed_at=not.is.null&select=completed_at,attempts&order=completed_at.desc&limit=500');
    $activity = [];
    $attemptsTotal = 0;
    $tz = new DateTimeZone('Asia/Manila');
    foreach ($history as $row) {
        $attemptsTotal += (int)($row['attempts'] ?? 0);
        if (empty($row['completed_at'])) continue;
        $day = (new DateTime($row['completed_at']))->setTimezone($tz)->format('Y-m-d');
        $activity[$day] = ($activity[$day] ?? 0) + 1;
    }
    $calendar = [];
    $today = new DateTimeImmutable('today', $tz);
    for ($i = 34; $i >= 0; $i--) {
        $day = $today->modify('-' . $i . ' days')->format('Y-m-d');
        $calendar[] = ['date' => $day, 'completed' => $activity[$day] ?? 0];
    }

    json_out([
        'xp' => (int)$me['xp'], 'seeds' => (int)$me['seeds'], 'streak' => (int)$me['streak'],
        'lessons_done' => $doneCount, 'lessons_total' => count($list),
        'mastery' => $mastery, 'achievements' => $achievements,
        'activity' => $calendar, 'attempts_total' => $attemptsTotal,
    ]);
}

$in = read_json();
$lessonId = (int)($in['lesson_id'] ?? 0);
$code = trim(substr((string)($in['code'] ?? ''), 0, 5000));
if ($code === '') fail('Write your solution before checking it.', 422);

$lesson = null; $next = null;
foreach ($list as $i => $l) {
    if ((int)$l['id'] === $lessonId) { $lesson = $l; $next = $list[$i + 1] ?? null; break; }
}
if (!$lesson) fail('Level not found', 404);
if ($lesson['status'] === 'locked') fail('That level is still locked', 403);

/* Re-check the lesson's published structural requirements on the server.
   The browser checker is for feedback; it is not the authority for rewards. */
$rules = is_array($lesson['rules']) ? $lesson['rules'] : [];
$required = $rules['mustContain'] ?? [];
if (!is_array($required)) $required = [];
foreach ($required as $fragment) {
    if (!is_string($fragment) || $fragment === '' || strpos($code, $fragment) === false) {
        fail('Your solution does not meet all of this lesson\'s requirements yet.', 422);
    }
}
$forbidden = $rules['mustNotContain'] ?? [];
if (is_array($forbidden)) {
    foreach ($forbidden as $fragment) {
        if (is_string($fragment) && $fragment !== '' && strpos($code, $fragment) !== false) {
            fail('Your solution uses something this lesson has not introduced yet.', 422);
        }
    }
}
$lines = substr_count($code, "\n") + 1;
if (isset($rules['minLines']) && $lines < (int)$rules['minLines']) fail('Add the missing lines to complete this solution.', 422);
if (isset($rules['maxLines']) && $lines > (int)$rules['maxLines']) fail('Your solution is longer than this challenge allows.', 422);

if ($lesson['status'] === 'done') {
    sb('PATCH', "/user_progress?user_id=eq.$uid&lesson_id=eq.$lessonId", ['best_code' => $code]);
    json_out(['awarded' => false, 'seeds' => (int)$me['seeds'], 'xp' => (int)$me['xp'],
        'streak' => (int)$me['streak'], 'next_id' => $next ? (int)$next['id'] : null]);
}

$tz = new DateTimeZone('Asia/Manila');
$now = new DateTimeImmutable('now', $tz);
$last = sb('GET', "/user_progress?user_id=eq.$uid&status=eq.done&order=completed_at.desc&limit=1&select=completed_at");
$streak = 1;
if ($last && !empty($last[0]['completed_at'])) {
    $lastDay = (new DateTimeImmutable($last[0]['completed_at']))->setTimezone($tz)->setTime(0, 0);
    $today = $now->setTime(0, 0);
    $gap = (int)$lastDay->diff($today)->format('%r%a');
    if ($gap === 0) $streak = max(1, (int)$me['streak']);
    elseif ($gap === 1) $streak = (int)$me['streak'] + 1;
}

$attempts = sb('GET', "/user_progress?user_id=eq.$uid&lesson_id=eq.$lessonId&select=attempts");
sb('POST', '/user_progress?on_conflict=user_id,lesson_id', [
    'user_id' => $me['id'], 'lesson_id' => $lessonId, 'status' => 'done', 'best_code' => $code,
    'attempts' => ((int)($attempts[0]['attempts'] ?? 0)) + 1, 'completed_at' => gmdate('c'),
], ['resolution=merge-duplicates', 'return=representation']);

$seeds = (int)$me['seeds'] + (int)$lesson['reward_seeds'];
$xp = (int)$me['xp'] + (int)$lesson['reward_xp'];
sb('PATCH', "/profiles?id=eq.$uid", ['seeds' => $seeds, 'xp' => $xp, 'streak' => $streak]);

json_out(['awarded' => true, 'seeds' => $seeds, 'xp' => $xp, 'streak' => $streak,
    'reward_seeds' => (int)$lesson['reward_seeds'], 'reward_xp' => (int)$lesson['reward_xp'],
    'next_id' => $next ? (int)$next['id'] : null]);
?>