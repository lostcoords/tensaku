class GreetingMailer < ApplicationMailer
  def welcome
    @name = "David"
    mail to: "david@example.com", subject: "Welcome"
  end
end
