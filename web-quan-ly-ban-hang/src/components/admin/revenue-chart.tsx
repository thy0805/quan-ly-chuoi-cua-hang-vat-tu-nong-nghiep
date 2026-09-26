const data = [
  { month: "T4", revenue: 410, cost: 292 },
  { month: "T5", revenue: 468, cost: 318 },
  { month: "T6", revenue: 445, cost: 305 },
  { month: "T7", revenue: 532, cost: 351 },
  { month: "T8", revenue: 590, cost: 386 },
  { month: "T9", revenue: 648, cost: 412 },
]

export function RevenueChart() {
  return (
    <div>
      <div className="mb-6 flex gap-5 text-xs text-muted-foreground">
        <span className="flex items-center gap-2"><span className="size-2 rounded-full bg-[#397555]" /> Doanh thu</span>
        <span className="flex items-center gap-2"><span className="size-2 rounded-full bg-[#d09a3e]" /> Chi phí</span>
      </div>
      <div className="grid h-60 grid-cols-6 items-end gap-3 border-b border-black/10">
        {data.map((item) => (
          <div key={item.month} className="flex h-full flex-col justify-end">
            <div className="flex flex-1 items-end justify-center gap-1.5">
              <div className="w-4 rounded-t-md bg-[#397555] sm:w-7" style={{ height: `${item.revenue / 7}%` }} title={`Doanh thu ${item.revenue} triệu`} />
              <div className="w-4 rounded-t-md bg-[#d09a3e]" style={{ height: `${item.cost / 7}%` }} title={`Chi phí ${item.cost} triệu`} />
            </div>
            <span className="py-3 text-center text-xs text-muted-foreground">{item.month}</span>
          </div>
        ))}
      </div>
    </div>
  )
}
