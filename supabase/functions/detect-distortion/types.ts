// =====================================================
// Type definitions for the Cognitive Distortion Detection Edge Function
// =====================================================
// Description: Request/response types with encryption handling
// Security: Edge Function handles all encryption/decryption
// Author: MindFriend Dev Team
// Date: 2026-01-23
// =====================================================

export type DistortionType =
  | "all_or_nothing"
  | "overgeneralization"
  | "mental_filter"
  | "disqualifying_positive"
  | "jumping_to_conclusions"
  | "magnification_minimization"
  | "emotional_reasoning"
  | "should_statements"
  | "labeling"
  | "personalization";

export type DetectionMethod = "llm" | "pattern";

export interface DetectDistortionRequest {
  text: string;
  sessionId: string;
  userId?: string; // Optional, extracted from JWT
}

export interface DetectedDistortion {
  type: DistortionType;
  confidence: number; // 0.0 - 1.0
  reasoning?: string; // Optional LLM reasoning
}

export interface DetectDistortionResponse {
  detected: boolean;
  distortion?: DetectedDistortion;
  detectionMethod: DetectionMethod;
}

export interface ErrorResponse {
  code: "TIMEOUT" | "LLM_FAILURE" | "INVALID_REQUEST" | "UNAUTHORIZED";
  message: string;
  details?: unknown;
}

export const DISTORTION_TYPE_LABELS: Record<DistortionType, string> = {
  all_or_nothing: "All-or-Nothing Thinking",
  overgeneralization: "Overgeneralization",
  mental_filter: "Mental Filter",
  disqualifying_positive: "Disqualifying the Positive",
  jumping_to_conclusions: "Jumping to Conclusions",
  magnification_minimization: "Magnification/Minimization",
  emotional_reasoning: "Emotional Reasoning",
  should_statements: "Should Statements",
  labeling: "Labeling",
  personalization: "Personalization",
};
