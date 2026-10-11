--!strict
-- Token-bucket rate limiter keyed by any value (usually a Player).
-- The clock is injected so the limiter can be unit tested.

local RateLimiter = {}
RateLimiter.__index = RateLimiter

type Bucket = { tokens: number, updatedAt: number }

export type RateLimiter = typeof(setmetatable(
	{} :: { capacity: number, refill: number, clock: () -> number, buckets: { [any]: Bucket } },
	RateLimiter
))

function RateLimiter.new(capacity: number, refillPerSecond: number, clock: (() -> number)?): RateLimiter
	return setmetatable({
		capacity = capacity,
		refill = refillPerSecond,
		clock = clock or os.clock,
		buckets = {},
	}, RateLimiter)
end

function RateLimiter.Allow(self: RateLimiter, key: any): boolean
	local now = self.clock()
	local bucket = self.buckets[key]
	if not bucket then
		bucket = { tokens = self.capacity, updatedAt = now }
		self.buckets[key] = bucket
	end
	bucket.tokens = math.min(self.capacity, bucket.tokens + (now - bucket.updatedAt) * self.refill)
	bucket.updatedAt = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

function RateLimiter.Forget(self: RateLimiter, key: any)
	self.buckets[key] = nil
end

return RateLimiter
