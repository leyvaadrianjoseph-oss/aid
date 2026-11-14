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

    foreach ($achievements as &$achievement) {
        $id = (int)$achievement['id'];
        $qualifies = ($metrics[$achievement['rule_key']] ?? 0) >= (int)$achievement['threshold'];
        if ($qualifies && !array_key_exists($id, $earnedIds)) {
            sb('POST', '/user_achievements?on_conflict=user_id,achievement_id', [
                'user_id' => $me['id'], 'achievement_id' => $id
            ], ['resolution=ignore-duplicates', 'return=minimal']);
            $earnedIds[$id] = gmdate('c');
        }
        $achievement['earned'] = array_key_exists($id, $earnedIds);
        $achievement['earned_at'] = $earnedIds[$id] ?? null;
    }
    unset($achievement);

    $concepts = [];
    foreach ($list as $lesson) {
        $name = $lesson['concept'] ?: $lesson['title'];
        $concepts[$name]['total'] = ($concepts[$name]['total'] ?? 0) + 1;
        $concepts[$name]['done'] = ($concepts[$name]['done'] ?? 0) + ($lesson['status'] === 'done' ? 1 : 0);
    }
    $mastery = [];
    foreach ($concepts as $name => $concept) {
        $mastery[] = ['concept' => $name, 'done' => $concept['done'], 'total' => $concept['total']];
    }

    $history = sb('GET', '/user_progress?user_id=eq.' . $uid . '&select=completed_at,attempts,status&order=completed_at.desc&limit=1000');
    $activity = [];
    $attemptsTotal = 0;
    $tz = new DateTimeZone('Asia/Manila');
    foreach ($history as $row) {
        $attemptsTotal += (int)($row['attempts'] ?? 0);
        if (($row['status'] ?? '') !== 'done' || empty($row['completed_at'])) continue;
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
$action = (string)($in['action'] ?? 'complete');
$lessonId = (int)($in['lesson_id'] ?? 0);
$code = trim(substr((string)($in['code'] ?? ''), 0, 5000));
$lesson = null;
$next = null;
foreach ($list as $index => $row) {
    if ((int)$row['id'] === $lessonId) {
        $lesson = $row;
        $next = $list[$index + 1] ?? null;
        break;
    }
}
if (!$lesson) fail('Level not found', 404);
if ($lesson['status'] === 'locked') fail('That level is still locked', 403);

if ($action === 'attempt') {
    [$attemptCode, $attemptResult] = sb_raw('POST', '/rpc/record_lesson_attempt', [
        'p_user_id' => $me['id'], 'p_lesson_id' => $lessonId, 'p_code' => $code
    ]);
    if ($attemptCode < 200 || $attemptCode >= 300 || !is_array($attemptResult)) {
        fail('Could not save this attempt. Try again.', 500);
    }
    json_out(['ok' => true, 'attempts' => (int)($attemptResult['attempts'] ?? 0)]);
}
if ($action !== 'complete') fail('Unknown progress action.', 422);
if ($code === '') fail('Write your solution before checking it.', 422);

/* Re-check published structural requirements before allowing a reward.
   The in-browser interpreter still provides the detailed output feedback. */
$rules = is_array($lesson['rules']) ? $lesson['rules'] : [];
$required = $rules['mustContain'] ?? [];
if (!is_array($required)) $required = [];
$normalizedCode = preg_replace('/\\s+/', '', $code);
foreach ($required as $fragment) {
    $normalizedFragment = is_string($fragment) ? preg_replace('/\\s+/', '', $fragment) : '';
    if ($normalizedFragment === '' || strpos($normalizedCode, $normalizedFragment) === false) {
        fail('Your solution does not meet all of this lesson\'s requirements yet.', 422);
    }
}
$forbidden = $rules['mustNotContain'] ?? [];
if (is_array($forbidden)) {
    foreach ($forbidden as $fragment) {
        $normalizedFragment = is_string($fragment) ? preg_replace('/\\s+/', '', $fragment) : '';
        if ($normalizedFragment !== '' && strpos($normalizedCode, $normalizedFragment) !== false) {
            fail('Your solution uses something this lesson has not introduced yet.', 422);
        }
    }
}
$lines = substr_count($code, "\n") + 1;
if (isset($rules['minLines']) && $lines < (int)$rules['minLines']) fail('Add the missing lines to complete this solution.', 422);
if (isset($rules['maxLines']) && $lines > (int)$rules['maxLines']) fail('Your solution is longer than this challenge allows.', 422);

[$completeCode, $completeResult] = sb_raw('POST', '/rpc/complete_lesson', [
    'p_user_id' => $me['id'],
    'p_lesson_id' => $lessonId,
    'p_code' => $code,
    'p_reward_seeds' => (int)$lesson['reward_seeds'],
    'p_reward_xp' => (int)$lesson['reward_xp']
]);
if ($completeCode < 200 || $completeCode >= 300 || !is_array($completeResult)) {
    fail('Could not save your lesson completion. Please try again.', 500);
}
$completeResult['next_id'] = $next ? (int)$next['id'] : null;
if (!empty($completeResult['awarded'])) {
    $completeResult['reward_seeds'] = (int)$lesson['reward_seeds'];
    $completeResult['reward_xp'] = (int)$lesson['reward_xp'];
}
json_out($completeResult);
?>