# frozen_string_literal: true

SmartAgent.define :brain_assistant do
  result = call_worker(:brain_assistant_worker, params, with_tools: false, with_history: true)
  if result.call_tools
    call_tools(result)
    params[:text] = 'Please continue.'
    result = call_worker(:brain_assistant_worker, params, with_tools: false, with_history: true)
  end
  result.content
end
