class SearchUsageReservation < ApplicationRecord
  # Reserved spend is never refunded, including failures and lost responses.
  def readonly?
    persisted?
  end
end
