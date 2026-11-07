class GreetingMailerPreview < ActionMailer::Preview
  def welcome
    GreetingMailer.welcome
  end
end
