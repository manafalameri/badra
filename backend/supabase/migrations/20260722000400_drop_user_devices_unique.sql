-- Drop the incorrect unique constraint that limited users to a single device.
-- Users should be able to have multiple devices (one per user_id + device_id).
ALTER TABLE badra_core.user_devices
DROP CONSTRAINT IF EXISTS user_devices_user_id_unique;
