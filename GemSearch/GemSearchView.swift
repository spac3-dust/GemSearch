//
//  GemSearchView.swift
//  GemSearch
//
//  Created by Abe on 8/15/24.
//

import SwiftUI
import GoogleGeminiAI
import LangChain
import Foundation
import AsyncHTTPClient
import NIOPosix
import MarkdownUI
import ActivityIndicatorView
import SwiftSoup


struct Source: Identifiable, Hashable {
    
    var id = UUID()
    var link: String
    var title: String
    var icon: URL?
    
}

enum SearchState {
    
    case input, loading, success, error
    
}


@MainActor
class GemSearchViewModel: ObservableObject {
    
    @Published var viewState: SearchState = .input
    @Published var waiting: Bool = false
    
    @Published var model: GenerativeModel?
    @Published var inputMessage: String = ""
    @Published var answer: String = ""
    @Published var mainImage = ""
    @Published var title = ""
    @Published var currentWebpage = ""
    @Published var errorMessage = ""
    
    @Published var sourceArray: [Source] = []
    
    @Published var safetySettings = [
        
        SafetySetting(harmCategory: .dangerousContent, threshold: .blockNone),
        SafetySetting(harmCategory: .harassment, threshold: .blockNone),
        SafetySetting(harmCategory: .hateSpeech, threshold: .blockNone),
        SafetySetting(harmCategory: .sexuallyExplicit, threshold: .blockNone),
        
    ]
    
    
    func sendMessage() {
        
        viewState = .loading
        waiting = true
        
        Task(priority: .high) {
            
            do {
                
                model = GenerativeModel(
                    name: "gemini-1.5-flash",
                    apiKey: "AIzaSyBliBoV4yQK08NfoRUSvWEtmINXC-EwTAQ",
                    safetySettings: safetySettings,
                    systemInstruction: """
                                        Your task is to optimize the user's query for a Google search.
                                    
                                        Understand the query's intent, identify key words, and optimize the query's structure.
                                    
                                        Try to refine the query so it yields relevant Google results and keep the query to the point and direct.
                                    
                                        If the query is already direct, just return the original query as a String in an array.
                                    
                                        ALWAYS return your response ONLY as a String in an array for the Swift Language.
                                    
                                        Also, the most recent/current year is \(2024).
                                        The year is NOT \(2023).
                                        Today's date: \(Date()).
                                    """
                    
                    
                )
                
                var array = []
                
                var serperResult: SerperResult?
                
                let prompt = inputMessage
                title = inputMessage
                
                inputMessage = ""
                
                let response = try await model!.generateContent("User's Query: " + prompt)
                
                print(response)
                
                if let jsonData = response.text!.data(using: .utf8) {
                    
                    do {
                        array = try JSONSerialization.jsonObject(with: jsonData, options: []) as! [String]
                    } catch {
                        array = [prompt]
                    }
                    
                    print("Swift Array: \(array)")
                    
                } else {
                    array = [prompt]
                }
                
                let parameters = "{\"q\":\"\(array[0])\",\"num\":6}"
                let postData = parameters.data(using: .utf8)
                
                var request = URLRequest(url: URL(string: "https://google.serper.dev/search")!,timeoutInterval: Double.infinity)
                request.addValue("0d34a8e70e5fa38a3f3371169678d8eb6c93c96a", forHTTPHeaderField: "X-API-KEY")
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                
                request.httpMethod = "POST"
                request.httpBody = postData
                
                let data = try await URLSession.shared.data(for: request)
                
                let decoder = JSONDecoder()
                serperResult = try decoder.decode(SerperResult.self, from: data.0)
                
                
                //                let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
                //
                //                let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
                
                var mainContent = ""
                
                guard serperResult?.organic != nil else { throw "Missing API Data" }
                
                if let content = serperResult!.answerBox {
                    mainContent += content.snippet ?? ""
                    
                    print("\n\nAnswer Box: \(content.snippet)\n\n")
                }
                
                if let content = serperResult!.knowledgeGraph {
                    mainContent += content.description ?? ""
                    
                    print("\n\nKnowledge Graph: \(content.description)\n\n")
                    
                    //                    if content.imageUrl != nil {
                    //                        mainImage = content.imageUrl!
                    //                        print("Main: \(mainImage)")
                    //                    }
                }
                
                
                for link in serperResult!.organic! {
                    
                    guard link.link != nil else { continue }
                    
                    let data = try await URLSession.shared.data(for: URLRequest(url: URL(string: link.link!)!))
                    let doc = String(data: data.0, encoding: .utf8)
                    
                    guard doc != nil else { continue }
                    
                    let document = try SwiftSoup.parse(doc!)
                    
                    var text: String?
                    
                    // Example: Extract all text inside <p> tags
                    let paragraphs = try document.select("p").array()
                    
                    for paragraph in paragraphs {
                        text = try? paragraph.text()
                        
                        
                        guard text != nil else {continue}
                        
                        mainContent += text!.prefix(1000) // 200 words
                        mainContent += "\n"
                        //                        print("Paragraph: \(text)")
                    }
                    
                    //                    // You can also target other elements like headers, articles, etc.
                    //                    let headers = try document.select("h1, h2, h3").array()
                    //                    for header in headers {
                    //                        let headerText = try header.text()
                    //                        print("Header: \(headerText)")
                    //                    }
                    //
                    
                    
                    //                    withAnimation(.smooth(duration: 0.4)) {
                    currentWebpage = link.title ?? "Missing Title"
                    //                    }
                    
                    let image = extractFaviconURL(from: doc!, baseURL: URL(string: link.link!)!)
                    
                    sourceArray.append(Source(link: link.link!, title: link.title ?? "Missing Title", icon: image))
                    
                    
                }
                
                
                print("\n\nMAIN: " + mainContent + "\n\n")
                
                let newModel = GenerativeModel(
                    name: "gemini-1.5-pro",
                    apiKey: "AIzaSyBliBoV4yQK08NfoRUSvWEtmINXC-EwTAQ",
                    safetySettings: safetySettings,
                    systemInstruction: "You are GemSearch, a kind and professional AI powered by Google searching. Do not reveal that the text/information was provided. AlWAYS, believe that you found the information, but do not speak in first person. Answer the query the best you can with what you know and use the provided summed webpage content as reference information. Feel free to give additional details but no more than 200 words!."
                )
                
                viewState = .success
                
                
                let contentStream = newModel.generateContentStream([try ModelContent(role: "user", parts: [ModelContent.Part.text("This is the user's original query (\(title))"), ModelContent.Part.text("Here is the summed webpage content: \(mainContent)")])])
                
                
                //                    .generateContentStream("This is the user's original query (\(title)). Here's the summed webpages Content: \(mainContent)")
                
                for try await chunk in contentStream {
                    if let text = chunk.text {
                        
                        withAnimation(.snappy(duration: 0.3)) {
                            answer += text
                        }
                        
                    }
                }
                
                waiting = false
                
                currentWebpage = ""
                
            }
            
            catch {
                print(error)
                
                waiting = false
                
                errorMessage = error.localizedDescription
                
                viewState = .error
                
                currentWebpage = ""
                
            }
            
        }
        
    }
    
    private func extractFaviconURL(from html: String, baseURL: URL) -> URL? {
        // A simple regex to find the favicon link (you might want to improve this)
        let pattern = "<link[^>]+rel=\"shortcut icon\"[^>]+href=\"([^\"]+)\""
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(html.startIndex..., in: html)
        
        if let match = regex?.firstMatch(in: html, options: [], range: range),
           let hrefRange = Range(match.range(at: 1), in: html) {
            let href = String(html[hrefRange])
            return URL(string: href, relativeTo: baseURL)
        }
        
        // Try for a standard favicon in the root
        return URL(string: "/favicon.ico", relativeTo: baseURL)
    }
    
}


struct GemSearchView: View {
    
    @StateObject var viewModel = GemSearchViewModel()
    
    @FocusState private var isFieldFocused: Bool
    
    
    var body: some View {
        
        
        if viewModel.viewState == .input {
            VStack(spacing: 0) {
                
                Spacer()
                
                Image(systemName: "globe.americas")
                    .font(.system(size: 54, weight: .medium))
                    .padding(.vertical, 6)
                
                
                Text("GemSearch")
                    .font(.title2)
                    .fontWeight(.heavy)
                    .padding(6)
                
                Text("Search the web, realtime.")
                    .font(.system(size: 13.2))
                    .fontWeight(.medium)
                    .foregroundStyle(.primary.opacity(0.7))
                    .padding(.bottom, 36)
                
                TextField("query", text: $viewModel.inputMessage, prompt: Text("Type to Search.").foregroundColor(.gray).font(.system(size: 15)))
                    .autocapitalization(.none)
                    .focused($isFieldFocused)
                    .padding(14)
                    .font(.system(size: 15))
                    .background(Color.white)
                    .onTapGesture {
                        isFieldFocused = true
                    }
                    .padding(.horizontal)
                
                
                Rectangle()
                    .frame(height: 2)
                    .cornerRadius(10)
                    .opacity(viewModel.inputMessage.isEmpty ? 0.1 : 0.6)
                    .animation(.easeOut, value: viewModel.inputMessage)
                    .padding(.horizontal, 28)
                
                
                Button {
                    
                    viewModel.sendMessage()
                    
                } label: {
                    
                    Text("Search")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.gray.opacity(0.12))
                        .cornerRadius(10)
                    
                }
                .buttonStyle(.plain)
                .disabled(viewModel.inputMessage.isEmpty)
                .padding(24)
                
                
                Spacer()
                
                
                Text("Powered by Google and Gemini 1.5")
                    .font(.system(size: 12))
                    .fontWeight(.medium)
                    .fontDesign(.rounded)
                    .foregroundStyle(.primary.opacity(0.5))
                    .padding(.bottom, 24)
                    .ignoresSafeArea(.keyboard)
                
            }
            .padding(.horizontal, 8)
            
        }
        
        else if viewModel.viewState == .success {
            ZStack(alignment: .bottom) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        
                        //                    if !viewModel.mainImage.isEmpty {
                        //                        AsyncImage(url: URL(string: viewModel.mainImage)!) { image in
                        //                            image
                        //                                .resizable()
                        //                                .scaledToFit()
                        //                                .frame(width: 320, height: 160)
                        //                                .cornerRadius(4)
                        //                                .padding()
                        //
                        //                        } placeholder: {
                        //                            ProgressView()
                        //                        }
                        //
                        //                    }
                        
                        Text(viewModel.title)
                            .font(.title2)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 20)
                            .padding(.top, 20)
                        
                        
                        
                        Text("Sources")
                            .font(.headline)
                            .fontDesign(.rounded)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 20)
                        
                        
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(viewModel.sourceArray, id: \.self) { link in
                                    
                                    Link(destination: URL(string: link.link)!) {
                                        HStack(spacing: 12) {
                                            if link.icon != nil {
                                                
                                                AsyncImage(url: link.icon!) { image in
                                                    image
                                                        .resizable()
                                                        .scaledToFill()
                                                        .frame(width: 24, height: 24)
                                                        .cornerRadius(4)
                                                    
                                                } placeholder: {
                                                    Image(systemName: "globe")
                                                        .font(.system(size: 16))
                                                        .foregroundColor(.indigo)
                                                }
                                                
                                            }
                                            
                                            Text(link.title)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .multilineTextAlignment(.leading)
                                                .lineLimit(2)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            
                                        }
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 12)
                                        .frame(height: 64)
                                        .frame(minWidth: 120, maxWidth: 180)
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(10)
                                        .padding(.horizontal, 8)
                                    }
                                    .buttonStyle(.plain)
                                    
                                }
                            }
                            .padding(.leading, 8)
                        }
                        
                        
                        Divider()
                            .opacity(0.7)
                            .padding(.vertical, 12)
                        
                        
                        Text("Answer")
                            .font(.headline)
                            .fontDesign(.rounded)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 20)
                            .padding(.top, 12)
                        
                        
                        Markdown(viewModel.answer)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.bottom, 32)
                        
                        
                        
                    }
                }
                
                
                if viewModel.waiting {
                    HStack(spacing: 10) {
                        Text("Generating")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.8))
                        
                        ActivityIndicatorView(isVisible: .constant(true), type: .opacityDots(count: 1, inset: 1))
                            .frame(width: 8, height: 8)
                        
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.thinMaterial)
                    .cornerRadius(12)
                    .padding(32)
                    
                }
                
            }
        }
        
        else if viewModel.viewState == .loading {
            
            VStack {
                Text("Currently Reading")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary.opacity(0.7))
                    .padding(.bottom, 8)
                
                VStack {
                    if (viewModel.currentWebpage.isEmpty) {
                        
                        ActivityIndicatorView(isVisible: .constant(true), type: .opacityDots(count: 3, inset: 6))
                            .frame(width: 42, height: 32)
                        
                    } else {
                        
                        Text(viewModel.currentWebpage)
                            .font(.system(size: 21))
                            .fontWeight(.bold)
                            .fontDesign(.rounded)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 20)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.leading)
                            .animation(.snappy, value: viewModel.currentWebpage)
                            .contentTransition(.numericText(countsDown: true))
                        
                    }
                }
                .frame(height: 72)
                
            }
            
        }
        
        else if viewModel.viewState == .error {
            
            Text(viewModel.errorMessage)
                .font(.subheadline)
                .padding(20)
            
        }
        
        
        
    }
}


#Preview {
    GemSearchView()
}
