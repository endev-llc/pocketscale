//
//  GeminiService.swift
//  pocketscale
//
//  Created by Jake Adams on 7/1/25.
//

import Foundation
import FirebaseAI
import UIKit

struct ConstituentFoodItem: Codable {
    let name: String
    let weight_grams: Int
}

struct WeightAnalysisResponse: Codable {
    let overall_food_item: String
    let constituent_food_items: [ConstituentFoodItem]
    let total_weight_grams: Int
    let confidence_percentage: Int
}

class GeminiService: ObservableObject {
    private let model: GenerativeModel
    
    init() {
        let generationConfig = GenerationConfig(
            temperature: 0.0,
            responseMIMEType: "application/json"
        )
        
        let systemInstruction = ModelContent(
            role: "system",
            parts: """
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
        )
        
        // Initialize the Gemini model using FirebaseAI
        model = FirebaseAI.firebaseAI().generativeModel(
            modelName: "gemini-2.5-flash",
            generationConfig: generationConfig,
            systemInstruction: systemInstruction
        )
    }
    
    // Compress image before sending to API
    private func compressImage(_ image: UIImage) -> UIImage? {
        // First, resize if the image is too large (optional but recommended)
        let maxDimension: CGFloat = 1024
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height)
        
        if scale < 1 {
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            // Compress the resized image
            if let resized = resizedImage,
               let compressedData = resized.jpegData(compressionQuality: 0.9) {
                return UIImage(data: compressedData)
            }
        }
        
        // If no resizing needed, just compress
        if let compressedData = image.jpegData(compressionQuality: 0.9) {
            return UIImage(data: compressedData)
        }
        
        return image // Return original if compression fails
    }
    
    func analyzeFood(image: UIImage) async throws -> WeightAnalysisResponse {
        do {
            // Compress the image before sending
            let compressedImage = compressImage(image) ?? image
            
            // Send the text prompt and compressed image to generateContent
            let response = try await model.generateContent(
                "Analyze and provide me with the weight of the item from the attached image.",
                compressedImage
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
                print("API Response: \(analysisResponse)")
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
