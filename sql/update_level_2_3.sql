-- Update the existing Level 2 and Level 3 lessons in Supabase.
-- Run once in the Supabase SQL Editor. This updates rows and does not insert duplicates.

update lessons
set
  goals = '["Use an if statement to check whether sun > 5", "Print Grow! when the condition is true", "Use else to print Wait when the condition is false"]'::jsonb,
  starter_code = E'sun = 8\n# Check whether the sun is bright enough for the plants\n',
  rules = '{"mustContain":["if sun > 5:","else:","print(\"Grow!\")","print(\"Wait\")"],"hint":"Write if sun > 5: and indent its print() line by 4 spaces. Add else: on its own line, then indent print(\"Wait\") by 4 spaces."}'::jsonb
where chapter_id = (select id from chapters where slug = 'first-sprouts')
  and title = 'Sunny or not';

update lessons
set
  goals = '["Write a for loop that uses range(3)", "Use the loop variable to number the plants starting at 1", "Print Water plant 1, Water plant 2 and Water plant 3 on separate lines"]'::jsonb,
  starter_code = E'# Use a for loop to water 3 plants, one line at a time\n',
  rules = '{"mustContain":["for i in range(3):","print(\"Water plant\", i + 1)"],"hint":"Write for i in range(3): and indent the loop body by 4 spaces. Use i + 1 when printing so the plant numbers start at 1."}'::jsonb
where chapter_id = (select id from chapters where slug = 'first-sprouts')
  and title = 'Water every plant';
