//
//  ContentView.swift
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


struct Source: Identifiable, Hashable {
    
    var id = UUID()
    var link: String
    var title: String
    var icon: URL?
    
}

enum SearchState {
    
    case input, loading, success, error
    
}


class ContentViewModel: ObservableObject {
    
    @Published var viewState: SearchState = .input
    
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
        
        Task(priority: .high) {
            
            do {
                
                model = GenerativeModel(
                    name: "gemini-1.5-flash",
                    apiKey: "",
                    safetySettings: safetySettings,
                    systemInstruction: """
                                        Your task is to optimize the user's query for a Google search.
                                        
                                        If the question has multiple parts, feel free to generalize the query if the parts fall under a general category and return it as a String in an array.
                                        Example: If I ask about Elon Musk's age and family, it can be generalized to 'About Elon Musk' or 'Elon Musk Background'. Do not use the keyword "Biography".
                                        If the question is already direct, just return the original query as a String in an array.
                                    
                                        ALWAYS return your response ONLY as a String in an array for the Swift Language.
                                    """
                    //                                If the parts do not fall under the same category, try to split the query into follow ups in array form.
                    //                                Example: What is Samsung and who is Lionel Messi, should just return What is Samsung. and Who is Lionel Messi.
                    //
                    //                                If a query needs several steps to solve, divide the query into follow-up steps into array form.
                    //                                Example: Where was the current Ballon Dor Winner Born? should return Who is the current Ballon Winner, and Where was they born?.
                    
                    
                )
                
                var array = []
                
                var user: Json4Swift_Base?
                
                let prompt = inputMessage
                title = inputMessage
                
                inputMessage = ""
                
                let response = try await model!.generateContent(prompt)
                
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
                
                
                var semaphore = DispatchSemaphore(value: 0)
                
                let parameters = "{\"q\":\"\(array[0])\",\"num\":7}"
                let postData = parameters.data(using: .utf8)
                
                var request = URLRequest(url: URL(string: "https://google.serper.dev/search")!,timeoutInterval: Double.infinity)
                request.addValue("0d34a8e70e5fa38a3f3371169678d8eb6c93c96a", forHTTPHeaderField: "X-API-KEY")
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                
                request.httpMethod = "POST"
                request.httpBody = postData
                
                let data = try await URLSession.shared.data(for: request)
                
                let decoder = JSONDecoder()
                user = try decoder.decode(Json4Swift_Base.self, from: data.0)
                
                
                let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
                
                let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
                
                defer {
                    try? httpClient.syncShutdown()
                }
                
                var mainContent = ""
                
                guard user?.organic != nil else { throw "Missing API Data" }
                
                if let content = user!.answerBox {
                    mainContent += content.snippet ?? ""
                }
                
                if let content = user!.knowledgeGraph {
                    mainContent += content.description ?? ""
                    
                    //                    if content.imageUrl != nil {
                    //                        mainImage = content.imageUrl!
                    //                        print("Main: \(mainImage)")
                    //                    }
                }
                
                
                for link in user!.organic! {
                    
                    guard link.link != nil else { continue }
                    
                    var request = HTTPClientRequest(url: link.link!)
                    
                    request.headers.add(name: "User-Agent", value: "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/115.0.5790.130 Mobile/15E148 Safari/604.1")
                    
                    request.method = .GET
                    
                    let response = try await httpClient.execute(request, timeout: .seconds(120))
                    
                    
                    let plain = String(buffer: try await response.body.collect(upTo: 1024 * 1024 * 32))
                    
                    let loader = HtmlLoader(html: plain, url: link.link!)
                    let doc = await loader.load()
                    
                    guard !doc.isEmpty else { continue }
                    
                    //                    withAnimation(.smooth(duration: 0.4)) {
                    currentWebpage = link.title ?? "Missing Title"
                    //                    }
                    
                    let image = extractFaviconURL(from: plain, baseURL: URL(string: link.link!)!)
                    
                    sourceArray.append(Source(link: link.link!, title: link.title ?? "Missing Title", icon: image))
                    
                    mainContent += doc.first!.page_content.prefix(1000) // 200 words
                    mainContent += "\n"
                    
                }
                
                
                let newModel = GenerativeModel(
                    name: "gemini-1.5-flash",
                    apiKey: "",
                    safetySettings: safetySettings,
                    systemInstruction: "You are GemSearch, an AI powered by google searching. Do not reveal that you found the data from webpages. Just answer the query directly in at least 100 words but no more tha 250."
                )
                
                viewState = .success
                
                let contentStream = newModel.generateContentStream("Here's the summed content of various webpages. Webpages Content: \(mainContent). This is the user's original query (\(inputMessage). Feel free to answer the original query with what you know and reference the summed webpages.")
                
                for try await chunk in contentStream {
                    if let text = chunk.text {
                        
                        answer += text
                        
                    }
                }
                
                
                currentWebpage = ""
                
            }
            
            catch {
                
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


struct ContentView: View {
    
    @StateObject var viewModel = ContentViewModel()
    
    @FocusState private var isFieldFocused: Bool
    
    
    var body: some View {
        
        
        if viewModel.viewState == .input {
            VStack(spacing: 0) {
                
                Spacer()
                
                Image(systemName: "globe")
                    .font(.system(size: 52))
                    .padding(.vertical, 6)
                
                
                Text("GemSearch")
                    .font(.title2)
                    .fontWeight(.bold)
                    .fontDesign(.monospaced)
                    .padding(8)
                
                Text("Search the web, realtime.")
                    .font(.system(size: 13))
                    .fontWeight(.medium)
                    .foregroundStyle(.primary.opacity(0.65))
                    .padding(.bottom, 32)
                
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
            
        }
        
        else if viewModel.viewState == .success {
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
                        .padding(.leading, 20)
                        .padding(.vertical, 12)
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
                        .padding(.top)
                    
                    
                    Markdown(viewModel.answer)
                        .font(.subheadline)
                        .padding(.horizontal)
                        .padding(.bottom, 32)
                    
                    
                    
                }
            }
        }
        
        else if viewModel.viewState == .loading {
            
            VStack {
                Text("Currently Reading")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .fontDesign(.monospaced)
                    .padding(.bottom, 8)
                
                if (viewModel.currentWebpage.isEmpty) {
                    
                    ActivityIndicatorView(isVisible: .constant(true), type: .opacityDots(count: 3, inset: 6))
                        .frame(width: 42, height: 32)
                    
                } else {
                    Text(viewModel.currentWebpage)
                        .font(.title3)
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
            
        }
        
        else if viewModel.viewState == .error {
            
            Text(viewModel.errorMessage)
                .font(.subheadline)
                .padding(20)
            
        }
        
        
        
    }
}


#Preview {
    ContentView()
}
