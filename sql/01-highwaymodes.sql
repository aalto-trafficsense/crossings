-- The highwaymodes table is used to connect OSM highway values
-- to our road classification flags

DROP TABLE IF EXISTS highwaymodes;

-- TODO: This table could be TEMPORARY
CREATE UNLOGGED TABLE highwaymodes (
  highway  text PRIMARY KEY,
  motorcar boolean NOT NULL,
  bicycle  boolean NOT NULL,
  foot     boolean NOT NULL
);

-- PostgreSQL accepts both YES and yes, but YES is used to visually
-- distinquish between true and false values
-- TODO: Remove unused rows such as elevator
INSERT INTO highwaymodes
  (highway,         motorcar, bicycle, foot)
VALUES
  ('access',        'YES',    'YES',   'YES'),
  ('cycleway',      'no',     'YES',   'YES'),
  ('elevator',      'no',     'no',    'YES'),
  ('footway',       'no',     'YES',   'YES'),
  ('living_street', 'YES',    'YES',   'YES'),
  ('motorway',      'YES',    'no',    'no'),
  ('motorway_link', 'YES',    'no',    'no'),
  ('path',          'no',     'YES',   'YES'),
  ('pedestrian',    'no',     'YES',   'YES'),
  ('primary',       'YES',    'YES',   'YES'),
  ('primary_link',  'YES',    'YES',   'YES'),
  ('residential',   'YES',    'YES',   'YES'),
  ('secondary',     'YES',    'YES',   'YES'),
  ('steps',         'no',     'no',    'YES'),
  ('tertiary',      'YES',    'YES',   'YES'),
  ('tertiary_link', 'YES',    'YES',   'YES'),
  ('trunk',         'YES',    'no',    'no'),
  ('track',         'no',     'YES',   'YES'),
  ('unclassified',  'YES',    'no',    'no');
