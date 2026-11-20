-- ============================================================
-- Enable full record delivery for Realtime on payment_requests
-- ============================================================
-- Realtime can only deliver complete NEW/OLD records to subscribers
-- when the table uses REPLICA IDENTITY FULL. Without it, status-change
-- events (approved/rejected/expired) reach clients with partial payloads.
ALTER TABLE badra_core.payment_requests REPLICA IDENTITY FULL;