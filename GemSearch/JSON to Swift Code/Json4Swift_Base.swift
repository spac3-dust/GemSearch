/* 
Copyright (c) 2024 Swift Models Generated from JSON powered by http://www.json4swift.com

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

For support, please feel free to contact me at https://www.linkedin.com/in/syedabsar

*/

import Foundation
struct Json4Swift_Base : Codable {
	let searchParameters : SearchParameters?
	let answerBox : AnswerBox?
	let knowledgeGraph : KnowledgeGraph?
	let organic : [Organic]?
	let images : [Images]?
	let peopleAlsoAsk : [PeopleAlsoAsk]?
	let relatedSearches : [RelatedSearches]?

	enum CodingKeys: String, CodingKey {

		case searchParameters = "searchParameters"
		case answerBox = "answerBox"
		case knowledgeGraph = "knowledgeGraph"
		case organic = "organic"
		case images = "images"
		case peopleAlsoAsk = "peopleAlsoAsk"
		case relatedSearches = "relatedSearches"
	}

	init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		searchParameters = try values.decodeIfPresent(SearchParameters.self, forKey: .searchParameters)
		answerBox = try values.decodeIfPresent(AnswerBox.self, forKey: .answerBox)
		knowledgeGraph = try values.decodeIfPresent(KnowledgeGraph.self, forKey: .knowledgeGraph)
		organic = try values.decodeIfPresent([Organic].self, forKey: .organic)
		images = try values.decodeIfPresent([Images].self, forKey: .images)
		peopleAlsoAsk = try values.decodeIfPresent([PeopleAlsoAsk].self, forKey: .peopleAlsoAsk)
		relatedSearches = try values.decodeIfPresent([RelatedSearches].self, forKey: .relatedSearches)
	}

}