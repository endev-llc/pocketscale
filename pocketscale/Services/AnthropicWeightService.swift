//
//  AnthropicWeightService.swift
//  pocketscale
//
//  Created by Jake Adams on 7/3/25.
//

import Foundation
import UIKit

enum AnthropicWeightError: LocalizedError {
    case invalidImage
    case networkError(Error)
    case invalidResponse
    case apiError(String)
    case missingAPIKey
    
    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Failed to process the image"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .apiError(let message):
            return message
        case .missingAPIKey:
            return "API key not found"
        }
    }
}

class AnthropicWeightService: ObservableObject {
    private let apiKey: String
    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    convenience init() throws {
        // Try to get API key from environment or plist
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "ANTHROPIC_API_KEY") as? String,
              !apiKey.isEmpty else {
            throw AnthropicWeightError.missingAPIKey
        }
        self.init(apiKey: apiKey)
    }
    
    func analyzeFood(image: UIImage) async throws -> WeightAnalysisResponse {
        // First, validate and compress the image
        guard let imageData = processImage(image) else {
            throw AnthropicWeightError.invalidImage
        }
        
        let base64Image = imageData.base64EncodedString()
        
        // Create the system prompt for weight analysis
        let systemPrompt = """
        You are the underlying scanner technology for the iOS app PocketScale. Your job is to analyze food images you're provided and assign the overall food item from each image a PRECISE and ACCURATE weight in grams. Every weight you assign must be provided in the form of a SINGLE NUMBER, NOT a range.

        CRITICAL: YOU MUST RESPOND ONLY WITH VALID JSON IN THE EXACT FORMAT BELOW:

        {
          "overall_food_item": "overall dish name",
          "constituent_food_items": [
            {
              "name": "food item name",
              "weight_grams": 0
            }
          ],
          "total_weight_grams": 0,
          "confidence_percentage": 0
        }

        RESPONSE REQUIREMENTS:

        Respond ONLY with valid JSON - no additional text, explanations, or formatting
        For "overall_food_item": Provide a single, elegant name for the overall food item or dish.
        For "constituent_food_items": List the primary food item(s) contained in the image. If the food item is a multi-ingredient dish with a known name, list that instead of each of its constituents.
        For "weight_grams": Provide a single integer number (no decimals, no ranges)
        For "total_weight_grams": Provide the combined total weight in grams of all food items as a single integer.
        For "confidence_percentage": Provide a single integer from 0-100 representing your confidence in the weight calculation.
        All field names must match exactly as shown above.
        All values must be appropriate data types (strings for names, integers for weights and confidence).
        """
        
        let userPrompt = "Analyze and provide me with the weight of the item from the attached image."
        
        // Construct the request body
        let body: [String: Any] = [
            "model": "claude-3-7-sonnet-latest",
            "max_tokens": 1000,
            "temperature": 0.1,
            "system": systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": userPrompt
                        ],
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ]
        ]
        
        // Create and configure the request
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            // Implement retry logic with exponential backoff
            let maxRetries = 3
            var currentRetry = 0
            var retryDelay = 1.0 // Initial delay in seconds
            
            while true {
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    
                    if let httpResponse = response as? HTTPURLResponse {
                        print("Response status code: \(httpResponse.statusCode)")
                        
                        // Handle success case
                        if (200...299).contains(httpResponse.statusCode) {
                            let result = try JSONDecoder().decode(AnthropicResponse.self, from: data)
                            
                            // Extract the response text
                            guard let responseText = result.content.first?.text else {
                                throw AnthropicWeightError.invalidResponse
                            }
                            
                            // Log token usage if available
                            if let usage = result.usage {
                                print("📊 API TOKENS - Input: \(usage.input_tokens), Output: \(usage.output_tokens), Total: \(usage.input_tokens + usage.output_tokens)")
                            }
                            
                            // Parse the JSON response
                            return try parseWeightAnalysisResponse(from: responseText)
                        }
                        
                        // Handle retryable errors
                        let shouldRetry = httpResponse.statusCode == 429 || // Too many requests
                                          httpResponse.statusCode == 500 || // Internal server error
                                          httpResponse.statusCode == 502 || // Bad gateway
                                          httpResponse.statusCode == 503 || // Service unavailable
                                          httpResponse.statusCode == 504 || // Gateway timeout
                                          httpResponse.statusCode == 529    // Overloaded
                        
                        let retriesLeft = currentRetry < maxRetries
                        
                        if shouldRetry && retriesLeft {
                            currentRetry += 1
                            print("Request failed with status \(httpResponse.statusCode). Retrying (\(currentRetry)/\(maxRetries)) after \(retryDelay) seconds...")
                            
                            // Wait with exponential backoff before retrying
                            try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                            
                            // Exponential backoff with jitter
                            retryDelay = min(30, retryDelay * 2 * (0.9 + Double.random(in: 0...0.2)))
                            
                            // Continue to next iteration for retry
                            continue
                        }
                        
                        // If we get here, either we shouldn't retry or we're out of retries
                        if let errorResponse = try? JSONDecoder().decode(AnthropicErrorResponse.self, from: data) {
                            throw AnthropicWeightError.apiError(errorResponse.error.message)
                        }
                        throw AnthropicWeightError.apiError("API request failed with status code: \(httpResponse.statusCode)")
                    }
                    
                    // No valid HTTP response
                    throw AnthropicWeightError.invalidResponse
                    
                } catch {
                    // Handle exceptions that might occur during the request
                    if error is AnthropicWeightError {
                        throw error // Pass through our custom errors
                    }
                    
                    // For network errors, we might want to retry
                    if currentRetry < maxRetries {
                        currentRetry += 1
                        print("Network error: \(error.localizedDescription). Retrying (\(currentRetry)/\(maxRetries)) after \(retryDelay) seconds...")
                        
                        // Wait with exponential backoff before retrying
                        try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                        
                        // Exponential backoff with jitter
                        retryDelay = min(30, retryDelay * 2 * (0.9 + Double.random(in: 0...0.2)))
                        
                        // Continue to next iteration for retry
                        continue
                    }
                    
                    throw AnthropicWeightError.networkError(error)
                }
            }
        } catch {
            print("Detailed error: \(error)")
            throw error
        }
    }
    
    private func parseWeightAnalysisResponse(from responseText: String) throws -> WeightAnalysisResponse {
        // Clean the response text to ensure it's valid JSON
        var cleanedResponse = responseText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        // Remove markdown code blocks if present
        if cleanedResponse.hasPrefix("```json") {
            cleanedResponse = String(cleanedResponse.dropFirst(7)) // Remove "```json"
        } else if cleanedResponse.hasPrefix("```") {
            cleanedResponse = String(cleanedResponse.dropFirst(3)) // Remove "```"
        }
        
        if cleanedResponse.hasSuffix("```") {
            cleanedResponse = String(cleanedResponse.dropLast(3)) // Remove closing "```"
        }
        
        // Final trim after removing markdown
        cleanedResponse = cleanedResponse.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        guard let jsonData = cleanedResponse.data(using: String.Encoding.utf8) else {
            throw AnthropicWeightError.apiError("Failed to convert response to data")
        }
        
        do {
            let analysisResponse = try JSONDecoder().decode(WeightAnalysisResponse.self, from: jsonData)
            return analysisResponse
        } catch {
            print("JSON Parsing Error: \(error)")
            print("Raw response: \(responseText)")
            print("Cleaned response: \(cleanedResponse)")
            throw AnthropicWeightError.apiError("Failed to parse JSON response: \(error.localizedDescription)")
        }
    }
    
    private func processImage(_ image: UIImage) -> Data? {
        // Resize image if needed
        let maxSize: CGFloat = 2048
        var processedImage = image
        
        if max(image.size.width, image.size.height) > maxSize {
            let scale = maxSize / max(image.size.width, image.size.height)
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            UIGraphicsBeginImageContext(newSize)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            if let resizedImage = UIGraphicsGetImageFromCurrentImageContext() {
                processedImage = resizedImage
            }
            UIGraphicsEndImageContext()
        }
        
        return processedImage.jpegData(compressionQuality: 0.8)
    }
}

// MARK: - Response Models

struct AnthropicResponse: Codable {
    let id: String
    let type: String
    let role: String
    let content: [AnthropicContentBlock]
    let model: String
    let stop_reason: String?
    let stop_sequence: String?
    let usage: AnthropicUsage?
}

struct AnthropicContentBlock: Codable {
    let type: String
    let text: String?
}

struct AnthropicUsage: Codable {
    let input_tokens: Int
    let output_tokens: Int
}

struct AnthropicErrorResponse: Codable {
    struct ErrorDetail: Codable {
        let message: String
        let type: String
    }
    let error: ErrorDetail
    let type: String
}
