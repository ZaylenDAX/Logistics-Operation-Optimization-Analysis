CREATE VIEW logistics_data AS
WITH trip_info AS(
    SELECT
        trip_id,
        t.driver_id,
        t.load_id,
        CONCAT(d.first_name, ' ', d.last_name) AS Driver_name,
        YEAR(GETDATE()) - YEAR(d.date_of_birth) AS Driver_Age,
        d.years_experience,
        truck_id,
        actual_distance_miles,
        dispatch_date
    FROM trips AS t
    INNER JOIN drivers AS d
    ON t.driver_id = d.driver_id
),

driver_info AS (
    SELECT t.truck_id, AVG(dm.on_time_delivery_rate) AS on_time_delivery_rate
    FROM driver_monthly_metrics AS dm
    INNER JOIN trips AS t
    ON dm.driver_id = t.driver_id
    GROUP BY t.truck_id
),

truck_info AS (
    SELECT
        truck_id,
        make AS Truck,
        YEAR(GETDATE()) - YEAR(acquisition_date) AS Truck_Age,
        acquisition_mileage
    FROM trucks
),

route_details AS (
    SELECT
        r.route_id,
        l.load_id,
        CONCAT(origin_state, '-', destination_state) AS route,
        destination_state,
        c.customer_id,
        c.customer_type,
        c.customer_name,
        c.primary_freight_type
    FROM routes AS r
    INNER JOIN loads AS l
    ON r.route_id = l.route_id
    INNER JOIN customers AS c
    ON l.customer_id = c.customer_id
),

route_info AS (
    SELECT
        t.load_id,
        t.truck_id,
        customer_id,
        route_id,
        route,
        destination_state,
        customer_name,
        customer_type,
        primary_freight_type
    FROM route_details AS rd
    INNER JOIN trips AS t
    ON rd.load_id = t.load_id
),

fuel_cost AS (
    SELECT
        truck_id,
        SUM(total_cost) AS fuel_cost
    FROM fuel_purchases
    GROUP BY truck_id
),

maintenance_cost AS (
    SELECT
        truck_id,
        SUM(maintenance_cost) AS maintenance_cost
    FROM truck_utilization_metrics
    GROUP BY truck_id
),

total_cost AS (
    SELECT
        fc.truck_id,
        fc.fuel_cost,
        mc.maintenance_cost,
        fc.fuel_cost + mc.maintenance_cost AS total_cost
    FROM fuel_cost AS fc
    INNER JOIN maintenance_cost AS mc
    ON fc.truck_id = mc.truck_id
),

revenue AS (
    SELECT
        truck_id,
        SUM(total_revenue) AS revenue,
        SUM(trips_completed) AS total_trips,
        AVG(utilization_rate) AS utilization_rate
    FROM truck_utilization_metrics
    GROUP BY truck_id
),

delivery_delays AS (
    SELECT
        trip_id,
        DATEDIFF(HOUR, scheduled_datetime, actual_datetime) AS delay_hours
    FROM delivery_events
    WHERE event_type = 'delivery'
)

SELECT
    ti.trip_id,
    ri.customer_id,
    ri.route_id,
    
    -- Truck and Driver Info
    ti.truck_id,
    ti.driver_id,
    ti.Driver_name,
    ti.Driver_Age,
    ti.years_experience,
    tr.Truck,
    tr.Truck_Age,
    tr.acquisition_mileage,

    -- Trip Details
    ti.actual_distance_miles,
    ti.dispatch_date,

    -- Fleet Utilization Metrics
    FORMAT(r.utilization_rate, 'P') AS utilization_rate,

    -- Expenses 
    tc.fuel_cost,
    tc.maintenance_cost, 
    tc.total_cost, 
    tc.total_cost/ti.actual_distance_miles AS cost_per_mile,
    
    -- Revenue
    r.revenue, 

    -- Profit
    r.revenue - tc.total_cost AS profit,

    --Delivery Metrics
    FORMAT(di.on_time_delivery_rate, 'P') AS on_time_delivery_rate,

    -- Customer Details
    ri.customer_name,
    ri.customer_type,
    ri.primary_freight_type,

    -- Routes & Delivery State
    ri.route,
    ri.destination_state,

    -- Delivery delays
    dd.delay_hours,
    CASE WHEN dd.delay_hours > 0 THEN '0'
    ELSE '1'
    END AS on_time_flag

FROM trip_info AS ti
INNER JOIN total_cost AS tc
ON ti.truck_id = tc.truck_id
INNER JOIN revenue AS r
ON ti.truck_id = r.truck_id
INNER JOIN driver_info AS di
ON ti.truck_id = di.truck_id
INNER JOIN truck_info AS tr
ON ti.truck_id = tr.truck_id
INNER JOIN route_info AS ri
ON ti.load_id = ri.load_id
INNER JOIN delivery_delays AS dd
ON ti.trip_id = dd.trip_id