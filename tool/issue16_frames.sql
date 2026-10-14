-- Raw app-surface evidence, not a synthetic duration-based acceptance grade.
SELECT p.name AS process_name, a.layer_name, a.surface_frame_token,
       a.display_frame_token, a.ts AS actual_start_ns, a.dur AS actual_duration_ns,
       e.ts AS expected_start_ns, e.dur AS expected_duration_ns,
       a.present_type, a.on_time_finish, a.jank_type, a.prediction_type
FROM actual_frame_timeline_slice a
JOIN process p USING (upid)
LEFT JOIN expected_frame_timeline_slice e
  ON e.upid = a.upid AND e.surface_frame_token = a.surface_frame_token
     AND e.layer_name = a.layer_name
WHERE p.name = 'com.xinlx227.whatever' AND a.surface_frame_token != 0
ORDER BY a.ts;
