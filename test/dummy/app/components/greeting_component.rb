class GreetingComponent < ViewComponent::Base
  def initialize(name:)
    @name = name
  end
end
