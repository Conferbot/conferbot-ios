//
//  KnowledgeBaseFixtures.swift
//  ConferbotTests
//
//  Help centre payloads captured from a local embed-server (:8001) on
//  2026-10-15, bot 6ab686f8d47ff029b76892f7, trimmed: two topics of two
//  articles, two recent articles, bodies cut to 400 characters, visitor
//  rows left out. Shapes are unchanged.
//

enum KnowledgeBaseFixtures {
    /// socket `fetched-chatbot-data` (chatbotData cut to the switch): knowledgeBaseData without bodies, `category` populated on recent articles and an id inside a topic.
    static let socketFetchedChatbotData = #"""
{
 "chatbotData": {
  "customizations": {
   "enableKnowledgeBase": true
  }
 },
 "visitor": {
  "country": null
 },
 "knowledgeBaseData": {
  "recentArticles": [
   {
    "_id": "6ab7ac0bb03f13ff22412c87",
    "slug": "how-to-use-conferbot-s-ai-chatbot-builder",
    "publishedDate": "2026-09-27T06:31:04.520Z",
    "viewCount": 4,
    "helpfulCount": 1,
    "title": "How to Use Conferbot's AI Chatbot Builder",
    "description": "Learn to create chatbots quickly with Conferbot's AI builder.",
    "category": {
     "_id": "6ab7abfcb03f13ff22412c38",
     "name": "Chatbot Creation"
    },
    "chatbotId": "6ab686f8d47ff029b76892f7",
    "author": {
     "_id": "642d37a520a83e213dcb95b7",
     "name": "admin"
    },
    "readingTime": 2,
    "wordCount": 315,
    "updatedAt": "2026-09-27T18:35:37.072Z"
   },
   {
    "_id": "6ab7ac19b03f13ff22412cd5",
    "slug": "how-to-set-up-live-chat-with-ai-chatbot-handoff",
    "publishedDate": "2026-09-27T06:31:04.520Z",
    "viewCount": 9,
    "helpfulCount": 1,
    "title": "How to Set Up Live Chat with AI Chatbot Handoff",
    "description": "Learn how live chat integrates with AI chatbot for seamless customer support.",
    "category": {
     "_id": "6ab7abfcb03f13ff22412c3c",
     "name": "AI Chatbot Features"
    },
    "chatbotId": "6ab686f8d47ff029b76892f7",
    "author": {
     "_id": "642d37a520a83e213dcb95b7",
     "name": "admin"
    },
    "readingTime": 2,
    "wordCount": 289,
    "updatedAt": "2026-10-11T12:51:45.179Z"
   }
  ],
  "categories": [
   {
    "_id": "6ab7abfcb03f13ff22412c36",
    "name": "Chatbot Essentials",
    "description": "Explore plans, templates, integrations, and AI-powered knowledge for your chatbots.",
    "icon": "plug",
    "articles": [
     {
      "_id": "6ab7ac01b03f13ff22412c4e",
      "slug": "how-to-integrate-openai-with-conferbot",
      "publishedDate": "2026-09-27T06:31:04.520Z",
      "viewCount": 4,
      "helpfulCount": 0,
      "title": "How to Integrate OpenAI with Conferbot",
      "description": "Learn how to integrate OpenAI with Conferbot for smarter chatbot interactions.",
      "category": "6ab7abfcb03f13ff22412c36",
      "chatbotId": "6ab686f8d47ff029b76892f7",
      "author": {
       "_id": "642d37a520a83e213dcb95b7",
       "name": "admin"
      },
      "readingTime": 2,
      "wordCount": 271,
      "updatedAt": "2026-09-27T18:57:13.827Z"
     },
     {
      "_id": "6ab7ac02b03f13ff22412c54",
      "slug": "what-is-an-nlp-chatbot-and-how-does-it-work",
      "publishedDate": "2026-09-27T06:31:04.520Z",
      "viewCount": 0,
      "helpfulCount": 0,
      "title": "What is an NLP Chatbot and How Does it Work?",
      "description": "Learn about NLP chatbots, their features, and benefits for your business.",
      "category": "6ab7abfcb03f13ff22412c36",
      "chatbotId": "6ab686f8d47ff029b76892f7",
      "author": {
       "_id": "642d37a520a83e213dcb95b7",
       "name": "admin"
      },
      "readingTime": 2,
      "wordCount": 234,
      "updatedAt": "2026-09-27T06:31:04.521Z"
     }
    ]
   },
   {
    "_id": "6ab7abfcb03f13ff22412c38",
    "name": "Chatbot Creation",
    "description": "Explore tools and insights for building and managing AI chatbots effortlessly.",
    "icon": "code",
    "articles": [
     {
      "_id": "6ab7ac0bb03f13ff22412c87",
      "slug": "how-to-use-conferbot-s-ai-chatbot-builder",
      "publishedDate": "2026-09-27T06:31:04.520Z",
      "viewCount": 4,
      "helpfulCount": 1,
      "title": "How to Use Conferbot's AI Chatbot Builder",
      "description": "Learn to create chatbots quickly with Conferbot's AI builder.",
      "category": "6ab7abfcb03f13ff22412c38",
      "chatbotId": "6ab686f8d47ff029b76892f7",
      "author": {
       "_id": "642d37a520a83e213dcb95b7",
       "name": "admin"
      },
      "readingTime": 2,
      "wordCount": 315,
      "updatedAt": "2026-09-27T18:35:37.072Z"
     },
     {
      "_id": "6ab7ac0cb03f13ff22412c8d",
      "slug": "how-to-use-rich-media-in-your-conferbot-chatbot",
      "publishedDate": "2026-09-27T06:31:04.520Z",
      "viewCount": 0,
      "helpfulCount": 0,
      "title": "How to Use Rich Media in Your Conferbot Chatbot",
      "description": "Enhance your chatbot with rich media for better engagement.",
      "category": "6ab7abfcb03f13ff22412c38",
      "chatbotId": "6ab686f8d47ff029b76892f7",
      "author": {
       "_id": "642d37a520a83e213dcb95b7",
       "name": "admin"
      },
      "readingTime": 2,
      "wordCount": 263,
      "updatedAt": "2026-09-27T06:31:04.521Z"
     }
    ]
   }
  ]
 }
}
"""#

    /// REST GET /mobile/knowledge-base/articles (the same as /chatbot/:id/kb's knowledgeBaseData): {data: {recentArticles, categories}} with bodies.
    static let restArticles = #"""
{
 "success": true,
 "data": {
  "recentArticles": [
   {
    "_id": "6ab7ac0bb03f13ff22412c87",
    "slug": "how-to-use-conferbot-s-ai-chatbot-builder",
    "publishedDate": "2026-09-27T06:31:04.520Z",
    "viewCount": 4,
    "helpfulCount": 1,
    "title": "How to Use Conferbot's AI Chatbot Builder",
    "description": "Learn to create chatbots quickly with Conferbot's AI builder.",
    "content": "<p>Conferbot's AI Chatbot Builder allows you to create chatbots quickly by describing your desired chatbot in plain English. The AI handles conversation flow design, making the process fast and straightforward.</p><h2>Steps to Create a Chatbot</h2><ol><li><strong>Describe Your Chatbot:</strong> Tell the AI what you want your chatbot to do. For example, 'Create a lead generation bot for a real esta",
    "category": {
     "_id": "6ab7abfcb03f13ff22412c38",
     "name": "Chatbot Creation"
    },
    "chatbotId": "6ab686f8d47ff029b76892f7",
    "author": {
     "_id": "642d37a520a83e213dcb95b7",
     "name": "admin"
    },
    "readingTime": 2,
    "wordCount": 315,
    "updatedAt": "2026-09-27T18:35:37.072Z"
   },
   {
    "_id": "6ab7ac19b03f13ff22412cd5",
    "slug": "how-to-set-up-live-chat-with-ai-chatbot-handoff",
    "publishedDate": "2026-09-27T06:31:04.520Z",
    "viewCount": 9,
    "helpfulCount": 1,
    "title": "How to Set Up Live Chat with AI Chatbot Handoff",
    "description": "Learn how live chat integrates with AI chatbot for seamless customer support.",
    "content": "<p>Live chat with AI chatbot handoff combines human empathy with the efficiency of automation, providing a seamless customer support experience. This integration ensures that customers receive timely assistance while allowing human agents to focus on complex issues.</p><h2>Seamless Bot-to-Human Handoff</h2><p>Conversations automatically transfer from the chatbot to a human agent when necessary. Th",
    "category": {
     "_id": "6ab7abfcb03f13ff22412c3c",
     "name": "AI Chatbot Features"
    },
    "chatbotId": "6ab686f8d47ff029b76892f7",
    "author": {
     "_id": "642d37a520a83e213dcb95b7",
     "name": "admin"
    },
    "readingTime": 2,
    "wordCount": 289,
    "updatedAt": "2026-10-11T12:51:45.179Z"
   }
  ],
  "categories": [
   {
    "_id": "6ab7abfcb03f13ff22412c36",
    "name": "Chatbot Essentials",
    "description": "Explore plans, templates, integrations, and AI-powered knowledge for your chatbots.",
    "icon": "plug",
    "articles": [
     {
      "_id": "6ab7ac01b03f13ff22412c4e",
      "slug": "how-to-integrate-openai-with-conferbot",
      "publishedDate": "2026-09-27T06:31:04.520Z",
      "viewCount": 4,
      "helpfulCount": 0,
      "title": "How to Integrate OpenAI with Conferbot",
      "description": "Learn how to integrate OpenAI with Conferbot for smarter chatbot interactions.",
      "content": "<p>Integrating OpenAI with Conferbot enhances your chatbot's capabilities, enabling it to deliver intelligent, context-aware conversations. Here's a guide on how to set up OpenAI with Conferbot.</p><h2>Connecting Your OpenAI Model</h2><p>To integrate OpenAI with Conferbot, you need to connect your OpenAI API key. Follow these steps:</p><ol><li>Obtain your OpenAI API key from the OpenAI platform.</",
      "category": "6ab7abfcb03f13ff22412c36",
      "chatbotId": "6ab686f8d47ff029b76892f7",
      "author": {
       "_id": "642d37a520a83e213dcb95b7",
       "name": "admin"
      },
      "readingTime": 2,
      "wordCount": 271,
      "updatedAt": "2026-09-27T18:57:13.827Z"
     },
     {
      "_id": "6ab7ac02b03f13ff22412c54",
      "slug": "what-is-an-nlp-chatbot-and-how-does-it-work",
      "publishedDate": "2026-09-27T06:31:04.520Z",
      "viewCount": 0,
      "helpfulCount": 0,
      "title": "What is an NLP Chatbot and How Does it Work?",
      "description": "Learn about NLP chatbots, their features, and benefits for your business.",
      "content": "<p>An NLP chatbot uses Natural Language Processing to understand and respond to user queries intelligently, enhancing customer interaction.</p><h2>Understanding NLP Chatbots</h2><p>NLP, or Natural Language Processing, is a form of artificial intelligence that enables chatbots to understand, interpret, and respond to human language meaningfully. Unlike simple keyword-based bots, NLP chatbots compre",
      "category": "6ab7abfcb03f13ff22412c36",
      "chatbotId": "6ab686f8d47ff029b76892f7",
      "author": {
       "_id": "642d37a520a83e213dcb95b7",
       "name": "admin"
      },
      "readingTime": 2,
      "wordCount": 234,
      "updatedAt": "2026-09-27T06:31:04.521Z"
     }
    ]
   },
   {
    "_id": "6ab7abfcb03f13ff22412c38",
    "name": "Chatbot Creation",
    "description": "Explore tools and insights for building and managing AI chatbots effortlessly.",
    "icon": "code",
    "articles": [
     {
      "_id": "6ab7ac0bb03f13ff22412c87",
      "slug": "how-to-use-conferbot-s-ai-chatbot-builder",
      "publishedDate": "2026-09-27T06:31:04.520Z",
      "viewCount": 4,
      "helpfulCount": 1,
      "title": "How to Use Conferbot's AI Chatbot Builder",
      "description": "Learn to create chatbots quickly with Conferbot's AI builder.",
      "content": "<p>Conferbot's AI Chatbot Builder allows you to create chatbots quickly by describing your desired chatbot in plain English. The AI handles conversation flow design, making the process fast and straightforward.</p><h2>Steps to Create a Chatbot</h2><ol><li><strong>Describe Your Chatbot:</strong> Tell the AI what you want your chatbot to do. For example, 'Create a lead generation bot for a real esta",
      "category": "6ab7abfcb03f13ff22412c38",
      "chatbotId": "6ab686f8d47ff029b76892f7",
      "author": {
       "_id": "642d37a520a83e213dcb95b7",
       "name": "admin"
      },
      "readingTime": 2,
      "wordCount": 315,
      "updatedAt": "2026-09-27T18:35:37.072Z"
     },
     {
      "_id": "6ab7ac0cb03f13ff22412c8d",
      "slug": "how-to-use-rich-media-in-your-conferbot-chatbot",
      "publishedDate": "2026-09-27T06:31:04.520Z",
      "viewCount": 0,
      "helpfulCount": 0,
      "title": "How to Use Rich Media in Your Conferbot Chatbot",
      "description": "Enhance your chatbot with rich media for better engagement.",
      "content": "<p>Enhancing your chatbot with rich media like images, videos, and GIFs can significantly improve user engagement and conversion rates. Conferbot allows you to easily incorporate these elements without needing any design skills.</p><h2>Benefits of Rich Media</h2><ul><li><strong>Instant Visual Impact:</strong> Capture attention quickly with eye-catching visuals.</li><li><strong>Boost Conversions:</",
      "category": "6ab7abfcb03f13ff22412c38",
      "chatbotId": "6ab686f8d47ff029b76892f7",
      "author": {
       "_id": "642d37a520a83e213dcb95b7",
       "name": "admin"
      },
      "readingTime": 2,
      "wordCount": 263,
      "updatedAt": "2026-09-27T06:31:04.521Z"
     }
    ]
   }
  ]
 }
}
"""#

    /// REST GET /mobile/knowledge-base/search?query=integrate: {data: [article]}, every field, createdAt with milliseconds.
    static let restSearch = #"""
{
 "success": true,
 "data": [
  {
   "_id": "6ab7ac19b03f13ff22412cd5",
   "slug": "how-to-set-up-live-chat-with-ai-chatbot-handoff",
   "approved": true,
   "reviewStatus": "published",
   "publishedDate": "2026-09-27T06:31:04.520Z",
   "aiGenerated": true,
   "sourceType": "url",
   "sourceStale": false,
   "staleReason": null,
   "version": 2,
   "viewCount": 9,
   "uniqueViewCount": 0,
   "helpfulCount": 1,
   "notHelpfulCount": 0,
   "averageRating": 0,
   "totalRatings": 1,
   "searchImpressions": 0,
   "searchClicks": 0,
   "title": "How to Set Up Live Chat with AI Chatbot Handoff",
   "description": "Learn how live chat integrates with AI chatbot for seamless customer support.",
   "content": "<p>Live chat with AI chatbot handoff combines human empathy with the efficiency of automation, providing a seamless customer support experience. This integration ensures that customers receive timely assistance while allowing human agents to focus on complex issues.</p><h2>Seamless Bot-to-Human Handoff</h2><p>Conversations automatically transfer from the chatbot to a human agent when necessary. Th",
   "category": {
    "_id": "6ab7abfcb03f13ff22412c3c",
    "name": "AI Chatbot Features"
   },
   "chatbotId": "6ab686f8d47ff029b76892f7",
   "author": {
    "_id": "642d37a520a83e213dcb95b7",
    "name": "admin"
   },
   "readingTime": 2,
   "wordCount": 289,
   "sourceUrl": "https://www.conferbot.com/features/livechat",
   "createdAt": "2026-09-26T11:27:21.633Z",
   "updatedAt": "2026-10-11T12:51:45.179Z",
   "__v": 0,
   "lastAIUpdate": "2026-09-26T11:35:32.596Z",
   "reviewedAt": "2026-09-27T06:31:04.520Z"
  },
  {
   "_id": "6ab7ac01b03f13ff22412c4e",
   "slug": "how-to-integrate-openai-with-conferbot",
   "approved": true,
   "reviewStatus": "published",
   "publishedDate": "2026-09-27T06:31:04.520Z",
   "aiGenerated": true,
   "sourceType": "url",
   "sourceStale": false,
   "staleReason": null,
   "version": 2,
   "viewCount": 4,
   "uniqueViewCount": 0,
   "helpfulCount": 0,
   "notHelpfulCount": 0,
   "averageRating": 0,
   "totalRatings": 0,
   "searchImpressions": 0,
   "searchClicks": 0,
   "title": "How to Integrate OpenAI with Conferbot",
   "description": "Learn how to integrate OpenAI with Conferbot for smarter chatbot interactions.",
   "content": "<p>Integrating OpenAI with Conferbot enhances your chatbot's capabilities, enabling it to deliver intelligent, context-aware conversations. Here's a guide on how to set up OpenAI with Conferbot.</p><h2>Connecting Your OpenAI Model</h2><p>To integrate OpenAI with Conferbot, you need to connect your OpenAI API key. Follow these steps:</p><ol><li>Obtain your OpenAI API key from the OpenAI platform.</",
   "category": {
    "_id": "6ab7abfcb03f13ff22412c36",
    "name": "Chatbot Essentials"
   },
   "chatbotId": "6ab686f8d47ff029b76892f7",
   "author": {
    "_id": "642d37a520a83e213dcb95b7",
    "name": "admin"
   },
   "readingTime": 2,
   "wordCount": 271,
   "sourceUrl": "https://www.conferbot.com/features/openai",
   "createdAt": "2026-09-26T11:26:57.970Z",
   "updatedAt": "2026-09-27T18:57:13.827Z",
   "__v": 0,
   "lastAIUpdate": "2026-09-26T11:35:31.774Z",
   "reviewedAt": "2026-09-27T06:31:04.520Z"
  }
 ]
}
"""#

    /// REST GET /mobile/knowledge-base/articles/:id: {data: article} with its body.
    static let restArticle = #"""
{
 "success": true,
 "data": {
  "_id": "6ab7ac0bb03f13ff22412c87",
  "slug": "how-to-use-conferbot-s-ai-chatbot-builder",
  "publishedDate": "2026-09-27T06:31:04.520Z",
  "viewCount": 4,
  "helpfulCount": 1,
  "title": "How to Use Conferbot's AI Chatbot Builder",
  "description": "Learn to create chatbots quickly with Conferbot's AI builder.",
  "content": "<p>Conferbot's AI Chatbot Builder allows you to create chatbots quickly by describing your desired chatbot in plain English. The AI handles conversation flow design, making the process fast and straightforward.</p><h2>Steps to Create a Chatbot</h2><ol><li><strong>Describe Your Chatbot:</strong> Tell the AI what you want your chatbot to do. For example, 'Create a lead generation bot for a real esta",
  "category": {
   "_id": "6ab7abfcb03f13ff22412c38",
   "name": "Chatbot Creation"
  },
  "chatbotId": "6ab686f8d47ff029b76892f7",
  "author": {
   "_id": "642d37a520a83e213dcb95b7",
   "name": "admin"
  },
  "readingTime": 2,
  "wordCount": 315,
  "updatedAt": "2026-09-27T18:35:37.072Z"
 }
}
"""#
}
