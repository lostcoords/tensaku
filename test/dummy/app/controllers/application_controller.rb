class ApplicationController < ActionController::Base
  around_action :switch_locale

  private

  def switch_locale(&)
    I18n.with_locale(params[:locale] || I18n.default_locale, &)
  end
end
