# Markdown pages carry data-md-source in development, so Tensaku can edit them.
Kiln::Content.source_positions = Rails.env.development?
