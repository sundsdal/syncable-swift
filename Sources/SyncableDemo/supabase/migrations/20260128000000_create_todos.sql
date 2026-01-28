-- Create todos table for Syncable demo
-- Run this in your Supabase SQL Editor or via supabase db push

-- Create the todos table
CREATE TABLE todos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted BOOLEAN NOT NULL DEFAULT false,
    title TEXT NOT NULL,
    is_completed BOOLEAN NOT NULL DEFAULT false
);

-- Create index for efficient user queries
CREATE INDEX todos_user_id_idx ON todos(user_id);
CREATE INDEX todos_updated_at_idx ON todos(updated_at);

-- Enable Row Level Security
ALTER TABLE todos ENABLE ROW LEVEL SECURITY;

-- RLS policy: users can only access their own todos
-- For testing without auth, comment this out and use the permissive policy below
CREATE POLICY "Users can manage their own todos"
ON todos FOR ALL
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- Alternative: Permissive policy for testing without authentication
-- Uncomment this and comment out the policy above if testing without auth
-- CREATE POLICY "Allow all for testing"
-- ON todos FOR ALL
-- USING (true)
-- WITH CHECK (true);

-- LWW conflict resolution trigger
-- Prevents older updates from overwriting newer data on the server
CREATE OR REPLACE FUNCTION discard_older_updates()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.updated_at > NEW.updated_at THEN
        RETURN OLD;  -- Keep the existing (newer) row
    END IF;
    RETURN NEW;  -- Allow the update
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER todos_lww_conflict_resolution
BEFORE UPDATE ON todos
FOR EACH ROW EXECUTE FUNCTION discard_older_updates();

-- Enable Realtime for this table
ALTER PUBLICATION supabase_realtime ADD TABLE todos;
