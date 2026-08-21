import Foundation

/// Prompts for command mode: rewrite selected text per a spoken instruction.
struct RewritePromptBuilder {
    func instructions() -> String {
        """
        You rewrite text according to the user's spoken instruction. Rules:
        - Follow the instruction exactly.
        - Preserve the meaning and facts of the original unless the instruction \
        says to change them.
        - Keep the original language and formatting style unless instructed otherwise.
        - Output only the rewritten text. No commentary, no quotes around it.
        """
    }

    func userPrompt(selection: String, instruction: String) -> String {
        """
        Instruction: \(instruction)

        Text:
        \(selection)
        """
    }
}
