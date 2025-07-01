//
//  GeminiService.swift
//  pocketscale
//
//  Created by Jake Adams on 7/1/25.
//

import Foundation
import FirebaseAI
import UIKit

struct FoodItem: Codable {
    let name: String
    let weight_grams: Int
}

struct WeightAnalysisResponse: Codable {
    let food_items: [FoodItem]
    let total_weight_grams: Int
    let confidence_percentage: Int
}

class GeminiService: ObservableObject {
    private let model: GenerativeModel
    
    init() {
        let generationConfig = GenerationConfig(
            temperature: 0.1,
            responseMIMEType: "application/json"
        )
        
        let systemInstruction = ModelContent(
            role: "system",
            parts: """
            You are the underlying scanner technology for the iOS app PocketScale. Your job is to analyze food images you're provided and assign the food item from each image a PRECISE and ACCURATE weight in grams. Every weight you assign must be provided in the form of a SINGLE NUMBER, NOT a range.
            
            CRITICAL: YOU MUST RESPOND ONLY WITH VALID JSON IN THE EXACT FORMAT BELOW:
            
            {
              "food_items": [
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
            For "food_items": List the primary food item(s) contained in the image. If the food item is a multi-ingredient dish with a known name, list that instead of each of its constituents
            For "weight_grams": Provide a single integer number (no decimals, no ranges)
            For "total_weight_grams": Provide the combined total weight in grams of all food items as a single integer
            For "confidence_percentage": Provide a single integer from 0-100 representing your confidence in the weight calculation
            All field names must match exactly as shown above
            All values must be appropriate data types (strings for names, integers for weights and confidence)
            """
        )
        
        // Initialize the Gemini model using FirebaseAI
        model = FirebaseAI.firebaseAI().generativeModel(
            modelName: "gemini-2.5-pro",
            generationConfig: generationConfig,
            systemInstruction: systemInstruction
        )
    }
    
    func analyzeFood(image: UIImage) async throws -> WeightAnalysisResponse {
        do {
            // Send the text prompt and image directly to generateContent
            let response = try await model.generateContent(
                "Analyze and provide me with the weight of the item from the attached image.",
                image
            )
            
            guard let responseText = response.text else {
                throw NSError(domain: "APIError", code: 2, userInfo: [NSLocalizedDescriptionKey: "No response text received"])
            }
            
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
                throw NSError(domain: "JSONError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to convert response to data"])
            }
            
            do {
                let analysisResponse = try JSONDecoder().decode(WeightAnalysisResponse.self, from: jsonData)
                return analysisResponse
            } catch {
                print("JSON Parsing Error: \(error)")
                print("Raw response: \(responseText)")
                print("Cleaned response: \(cleanedResponse)")
                throw NSError(domain: "JSONError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to parse JSON response: \(error.localizedDescription)"])
            }
        } catch {
            print("Firebase AI Error: \(error)")
            throw NSError(domain: "APIError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to analyze image: \(error.localizedDescription)"])
        }
    }
}
