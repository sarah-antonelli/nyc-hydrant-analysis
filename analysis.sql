-- =============================================================================
-- NYC Hydrant Density Analysis. analysis.sql
-- Portfolio Project 2, Modern GIS Accelerator
--
-- Five progressive PostGIS queries that build up to a normalized density
-- analysis and a 100-ft coverage analysis.
--
-- Assumes:
--   - Database "gis" with PostGIS extension enabled
--   - Tables loaded:
--       nyc_neighborhoods (polygon, EPSG:4326, geom column called "wkb_geometry",
--                          attributes including "ntaname" and "boroname")
--       nyc_hydrants      (point,   EPSG:4326, geom column called "wkb_geometry",
--                          attributes including "gid")
--   - Spatial indexes on both geom columns (CREATE INDEX ... USING GIST (geom))
--
-- Run all queries:
--   psql -h localhost -U gis -d gis -f analysis.sql
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Query 1: Filter
--
-- Sanity check that the data loaded. Pull all neighborhoods in Manhattan.
-- Expected output: ~38 rows (Manhattan neighborhoods).
-- -----------------------------------------------------------------------------

SELECT ntaname, boroname
FROM nyc_neighborhoods
WHERE boroname = 'Manhattan'
ORDER BY ntaname;

-- -----------------------------------------------------------------------------
-- Query 2: Spatial join
--
-- Match each hydrant to the neighborhood that contains it, using
-- ST_Contains.
-- Expected output: one row per hydrant (~109,725) with the neighborhood name.
-- -----------------------------------------------------------------------------

SELECT h.gid, n.ntaname, n.boroname
FROM nyc_hydrants h, nyc_neighborhoods n
WHERE ST_Contains(n.wkb_geometry, h.wkb_geometry);

-- -----------------------------------------------------------------------------
-- Query 3: Aggregate
--
-- Count hydrants per neighborhood.
-- Expected output: 262 rows (one per neighborhood) with a hydrant_count.
-- -----------------------------------------------------------------------------

SELECT n.ntaname,
       COUNT(h.*) AS hydrant_count
FROM nyc_hydrants h
JOIN nyc_neighborhoods n 
     ON ST_Contains(n.wkb_geometry, h.wkb_geometry)
GROUP BY n.ntaname
ORDER BY hydrant_count DESC;

-- -----------------------------------------------------------------------------
-- Query 4: Normalize (this is your headline result)
--
-- Compute density per square kilometer. Reproject to EPSG:2263
-- (NY State Plane Long Island, feet) before computing area, then convert
-- square feet to square kilometers.
-- Expected output: 262 rows with hydrant_count, area_km2, density_per_km2.
-- -----------------------------------------------------------------------------

SELECT 
       n.ntaname,
       COUNT(h.*) AS hydrant_count, 
       ROUND((ST_Area(ST_Transform(n.wkb_geometry, 2263)) / 10763910.42)::numeric, 2)  AS area_km2,
       ROUND((COUNT(h.*) / (ST_Area(ST_Transform(n.wkb_geometry, 2263)) / 10763910.42))::numeric, 2) AS density_per_km2
FROM nyc_hydrants h
JOIN nyc_neighborhoods n 
     ON ST_Contains(n.wkb_geometry, h.wkb_geometry)
GROUP BY n.ntaname, n.wkb_geometry  
ORDER BY density_per_km2 DESC;

-- -----------------------------------------------------------------------------
-- Query 5: Buffer + Union + Intersection (coverage analysis)
--
-- For each neighborhood, what percent of its area is within 100 meters
-- of a hydrant? This is the deeper finding.
-- Expected output: 262 rows with neighborhood, area_km2, covered_pct.
-- -----------------------------------------------------------------------------

WITH hydrant_coverage AS (
     SELECT 
          ST_Union(ST_Buffer(ST_Transform(wkb_geometry, 2263), 100)) AS coverage_geom
     FROM nyc_hydrants
)
SELECT 
     n.ntaname,
     ROUND((ST_Area(ST_Transform(n.wkb_geometry, 2263)) / 10763910.42)::numeric, 2) AS area_km2,
     ROUND((ST_Area(ST_Intersection(ST_Transform(n.wkb_geometry,2263), hc.coverage_geom)) / (ST_Area(ST_Transform(n.wkb_geometry, 2263))) * 100)::numeric, 2) AS covered_pct
FROM nyc_neighborhoods n, hydrant_coverage hc
ORDER BY covered_pct DESC;