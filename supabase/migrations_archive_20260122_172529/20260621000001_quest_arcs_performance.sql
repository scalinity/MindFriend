-- Quest Arcs Performance Optimizations
-- Adds indexes and aggregation function for efficient step counting

-- Add standalone index for step counting queries (prevents N+1)
CREATE INDEX IF NOT EXISTS idx_quest_arc_steps_arc_id_only 
  ON quest_arc_steps(arc_id);

-- Add covering index for active arc lookups with arc join
CREATE INDEX IF NOT EXISTS idx_user_quest_arcs_active_covering
  ON user_quest_arcs(user_id, arc_id)
  WHERE status = 'active';

-- Add database function for efficient step counting (prevents transferring all rows)
CREATE OR REPLACE FUNCTION get_arc_step_counts(arc_ids UUID[])
RETURNS TABLE (arc_id UUID, step_count BIGINT) AS $$
BEGIN
  RETURN QUERY
  SELECT qas.arc_id, COUNT(*)::BIGINT
  FROM quest_arc_steps qas
  WHERE qas.arc_id = ANY(arc_ids)
  GROUP BY qas.arc_id;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION get_arc_step_counts(UUID[]) TO authenticated;
GRANT EXECUTE ON FUNCTION get_arc_step_counts(UUID[]) TO anon;
