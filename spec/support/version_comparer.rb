class VersionComparer
  def initialize(version)
    @version = Gem::Version.new(version)
  end

  include Comparable
  def <=>(other)
    @version <=> Gem::Version.new(other)
  end
end
