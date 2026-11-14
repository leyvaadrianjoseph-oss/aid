-- Additional Adventure chapters for the existing beginner Python interpreter.
-- Run after sql/seed.sql. Idempotent: existing chapters and lessons are not duplicated.

insert into chapters(slug, title, blurb, sort_order, is_published)
values
  ('text-and-lists', 'Text & Tiny Collections', 'Work with text, comparisons, booleans and lists.', 2, true),
  ('loops-and-patterns', 'Loops & Patterns', 'Repeat useful actions and process collections.', 3, true),
  ('garden-challenges', 'The Garden Challenge', 'Combine conditions, loops and collections to solve bigger quests.', 4, true)
on conflict (slug) do update
set title = excluded.title, blurb = excluded.blurb,
    sort_order = excluded.sort_order, is_published = true;

with lesson_data(
  chapter_slug, title, concept, goals, starter_code, expected_output,
  rules, reward_seeds, reward_xp, sort_order
) as (
  values
  ('text-and-lists','Polish the plant label','String methods',
   jsonb_build_array('Use .upper() to make the plant name uppercase','Print the transformed name'),
   'plant = "fern"\n# Make the plant name uppercase',
   'FERN',
   jsonb_build_object('mustContain',jsonb_build_array('.upper()','print('),'hint','Call plant.upper() to create uppercase text, then print the result.'),
   20,50,1),
  ('text-and-lists','Compare the water level','Comparisons',
   jsonb_build_array('Check whether water is at least 3','Print True when the condition is met'),
   'water = 4\n# Compare water with 3',
   'True',
   jsonb_build_object('mustContain',jsonb_build_array('>=','print('),'hint','Use water >= 3 inside print().'),
   20,50,2),
  ('text-and-lists','Choose a sunny day','Booleans',
   jsonb_build_array('Create a Boolean named sunny','Print the Boolean value'),
   '# Set sunny to True\n',
   'True',
   jsonb_build_object('mustContain',jsonb_build_array('sunny = True','print(sunny)'),'hint','Boolean values use capital letters: True or False.'),
   20,50,3),
  ('text-and-lists','Make a plant collection','Lists',
   jsonb_build_array('Create a list named plants with three plant names','Print the complete list'),
   '# Create a list with fern, rose and cactus\n',
   '[''fern'', ''rose'', ''cactus'']',
   jsonb_build_object('mustContain',jsonb_build_array('plants = [','print(plants)'),'hint','Put each quoted plant name inside square brackets, separated by commas.'),
   20,50,4),
  ('text-and-lists','Find the first plant','List indexes',
   jsonb_build_array('Use index 0 to access the first plant','Print the first plant'),
   'plants = ["fern", "rose", "cactus"]\n# Print the first item',
   'fern',
   jsonb_build_object('mustContain',jsonb_build_array('plants[0]','print('),'hint','List positions start at zero. Use plants[0].'),
   20,50,5),

  ('loops-and-patterns','Add a new seed','List methods',
   jsonb_build_array('Add "tulip" to the plants list with append()','Print the updated list'),
   'plants = ["fern", "rose"]\n# Add tulip to the list',
   '[''fern'', ''rose'', ''tulip'']',
   jsonb_build_object('mustContain',jsonb_build_array('.append("tulip")','print(plants)'),'hint','Use plants.append("tulip") to add one item at the end.'),
   25,60,1),
  ('loops-and-patterns','Count your plants','List length',
   jsonb_build_array('Use len() to count the items','Print the number of plants'),
   'plants = ["fern", "rose", "cactus", "tulip"]\n# Print how many plants are in the list',
   '4',
   jsonb_build_object('mustContain',jsonb_build_array('len(plants)','print('),'hint','len(plants) returns the number of items in the list.'),
   25,60,2),
  ('loops-and-patterns','Visit every plant','Loop through a list',
   jsonb_build_array('Use a for loop to visit every plant','Print each plant name on its own line'),
   'plants = ["fern", "rose", "cactus"]\n# Loop through the list and print each plant',
   'fern\nrose\ncactus',
   jsonb_build_object('mustContain',jsonb_build_array('for plant in plants:','print(plant)'),'hint','Use for plant in plants: and indent print(plant) by four spaces.'),
   25,60,3),
  ('loops-and-patterns','Drain the watering can','While loops',
   jsonb_build_array('Repeat while water is greater than zero','Print the water amount','Decrease water by one each time'),
   'water = 3\n# Use a while loop to count down',
   '3\n2\n1',
   jsonb_build_object('mustContain',jsonb_build_array('while water > 0:','print(water)','water -= 1'),'hint','Inside the loop, print water and then subtract one with water -= 1.'),
   25,60,4),
  ('loops-and-patterns','Add up the harvest','List totals',
   jsonb_build_array('Use sum() to add all harvest amounts','Print the total'),
   'harvest = [2, 4, 6]\n# Print the total harvest',
   '12',
   jsonb_build_object('mustContain',jsonb_build_array('sum(harvest)','print('),'hint','sum(harvest) adds every number in the list.'),
   25,60,5),

  ('garden-challenges','Check the garden conditions','Combined conditions',
   jsonb_build_array('Check that the sun is above 5 and water is above 2','Print Ready when both are true'),
   'sun = 8\nwater = 4\n# Check both conditions',
   'Ready',
   jsonb_build_object('mustContain',jsonb_build_array('if sun > 5 and water > 2:','print("Ready")'),'hint','Join both comparisons with and, then indent the print statement.'),
   30,70,1),
  ('garden-challenges','Find a flower','Membership',
   jsonb_build_array('Check whether "rose" is in the plants list','Print Found when it exists'),
   'plants = ["fern", "rose", "cactus"]\n# Check whether rose is in the list',
   'Found',
   jsonb_build_object('mustContain',jsonb_build_array('"rose" in plants','print("Found")'),'hint','Use if "rose" in plants: and indent print("Found").'),
   30,70,2),
  ('garden-challenges','Stop at the cactus','Break a loop',
   jsonb_build_array('Loop through the plant names','Stop the loop when the plant is cactus','Print each plant before cactus'),
   'plants = ["fern", "rose", "cactus", "tulip"]\n# Stop when you reach cactus',
   'fern\nrose',
   jsonb_build_object('mustContain',jsonb_build_array('for plant in plants:','if plant == "cactus":','break','print(plant)'),'hint','Check for cactus inside the loop, break before printing it, then print other plants.'),
   30,70,3),
  ('garden-challenges','Skip the empty plot','Continue a loop',
   jsonb_build_array('Loop through plot numbers 1 to 4','Skip plot 2 with continue','Print the other plot numbers'),
   '# Use range(1, 5) to visit four plots',
   '1\n3\n4',
   jsonb_build_object('mustContain',jsonb_build_array('for plot in range(1, 5):','if plot == 2:','continue','print(plot)'),'hint','Use continue when plot equals 2 so the print line is skipped for that turn.'),
   30,70,4),
  ('garden-challenges','Sort the seed counts','Sorting lists',
   jsonb_build_array('Sort the numbers from smallest to largest','Print the sorted list'),
   'counts = [5, 2, 8, 1]\n# Sort the list and print it',
   '[1, 2, 5, 8]',
   jsonb_build_object('mustContain',jsonb_build_array('counts.sort()','print(counts)'),'hint','Call counts.sort() before print(counts).'),
   30,70,5)
)
insert into lessons(
  chapter_id,title,concept,goals,starter_code,expected_output,rules,
  reward_seeds,reward_xp,sort_order
)
select c.id,d.title,d.concept,d.goals,d.starter_code,d.expected_output,d.rules,
       d.reward_seeds,d.reward_xp,d.sort_order
from lesson_data d
join chapters c on c.slug=d.chapter_slug
where not exists (
  select 1 from lessons l
  where l.chapter_id=c.id and lower(l.title)=lower(d.title)
);
