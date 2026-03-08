#!/usr/bin/env python3
"""Patches ragService.js askQuestion method with improved prompt and relevance filtering."""
import re

PATCH = r'''  // RAG_PROMPT_PATCH
  async askQuestion(question) {
    try {
      const response = await axios.post(`${this.baseUrl}/context`, {
        question,
        max_sources: 5
      });
      const { context, sources } = response.data;

      // Fetch full content for top sources (context endpoint returns them ranked by relevance)
      let enhancedContext = context;
      if (sources && sources.length > 0) {
        const relevant = sources.slice(0, 3);

        const fullDocContents = await Promise.all(
          relevant.map(async (source) => {
            if (source.doc_id) {
              try {
                const fullContent = await paperlessService.getDocumentContent(source.doc_id);
                return '[' + (source.title || 'Document') + ']:\n' + fullContent;
              } catch (error) { return ''; }
            }
            return '';
          })
        );
        enhancedContext = fullDocContents.filter(c => c).join('\n\n');
      }

      const aiService = AIServiceFactory.getService();
      const ragInstructions = process.env.RAG_PROMPT || 'You are a document assistant. Answer based on the documents provided. Be concise. If listing documents, show title and key details. If the documents are not relevant to the question, say so.';
      const prompt = ragInstructions + '\n\nQuestion: ' + question + '\n\nDocuments:\n' + enhancedContext;

      let answer;
      try {
        answer = await aiService.generateText(prompt);
      } catch (error) {
        answer = "An error occurred while generating an answer.";
      }
      return { answer, sources };
    } catch (error) {
      throw new Error("An error occurred while processing your question.");
    }
  }'''

with open('/app/services/ragService.js', 'r') as f:
    content = f.read()

pattern = r'  async askQuestion\(question\) \{.*?\n  \}'
# Escape backslashes in replacement to prevent re.sub interpreting \n as newlines
escaped_patch = PATCH.replace('\\', '\\\\')
content = re.sub(pattern, escaped_patch, content, count=1, flags=re.DOTALL)

with open('/app/services/ragService.js', 'w') as f:
    f.write(content)
print('OK')
