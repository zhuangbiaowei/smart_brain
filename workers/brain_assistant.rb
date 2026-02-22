# frozen_string_literal: true

SmartPrompt.define_worker :brain_assistant_worker do
  use 'silicon_flow'
  model 'Pro/moonshotai/Kimi-K2.5'
  sys_msg 'You are a concise assistant. Use the provided context to answer the latest user message. If evidence exists, prioritize it.'
  prompt :brain_assistant, { text: params[:text] }
  send_msg
end
