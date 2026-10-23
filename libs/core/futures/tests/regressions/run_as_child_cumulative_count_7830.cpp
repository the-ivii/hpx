//  Copyright (c) 2026 Pratyksh Gupta
//
//  SPDX-License-Identifier: BSL-1.0
//  Distributed under the Boost Software License, Version 1.0. (See accompanying
//  file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)

// This test verifies that run_as_child threads executed directly by their
// parent are included exactly once in the cumulative executed-thread count.

#include <hpx/future.hpp>
#include <hpx/init.hpp>
#include <hpx/modules/testing.hpp>
#include <hpx/modules/threading_base.hpp>
#include <hpx/runtime.hpp>
#include <hpx/thread.hpp>

#include <cstddef>
#include <cstdint>

namespace {

    constexpr std::int64_t child_count = 100;

    void test_policy(hpx::launch policy)
    {
        hpx::threads::thread_schedule_hint hint;
        hint.runs_as_child_mode(
            hpx::threads::thread_execution_hint::run_as_child);
        policy.set_hint(hint);

        auto* pool = hpx::this_thread::get_pool();
        HPX_TEST(pool != nullptr);
        if (pool == nullptr)
        {
            return;
        }

        pool->get_executed_threads(static_cast<std::size_t>(-1), true);

        hpx::threads::thread_id_type const parent = hpx::threads::get_self_id();
        std::int64_t inlined = 0;
        for (std::int64_t i = 0; i != child_count; ++i)
        {
            hpx::lcos::local::futures_factory<void()> task([&] {
                if (hpx::threads::get_thread_state(parent).state() ==
                    hpx::threads::thread_schedule_state::active)
                {
                    ++inlined;
                }
            });
            hpx::future<void> f = task.get_future();
            task.post("run_as_child count", policy);
            f.get();
        }

        HPX_TEST_EQ(inlined, child_count);
        HPX_TEST_EQ(
            pool->get_executed_threads(static_cast<std::size_t>(-1), false),
            child_count);
    }
}    // namespace

int hpx_main()
{
    HPX_TEST_EQ(hpx::get_os_thread_count(), std::size_t(1));

    test_policy(hpx::launch::async);

    // Let the scheduler release the queue entries left by async children.
    // Those entries must not increment the count a second time.
    auto* pool = hpx::this_thread::get_pool();
    HPX_TEST(pool != nullptr);
    for (std::int64_t i = 0; pool != nullptr && i != child_count &&
        pool->get_queue_length(static_cast<std::size_t>(-1), false) != 0;
        ++i)
    {
        hpx::this_thread::yield();
    }

    if (pool != nullptr)
    {
        HPX_TEST_EQ(pool->get_queue_length(static_cast<std::size_t>(-1), false),
            std::int64_t(0));
        HPX_TEST_EQ(
            pool->get_executed_threads(static_cast<std::size_t>(-1), false),
            child_count);
    }

    test_policy(hpx::launch::fork);

    return hpx::local::finalize();
}

int main(int argc, char* argv[])
{
    HPX_TEST_EQ_MSG(hpx::local::init(hpx_main, argc, argv), 0,
        "HPX main exited with non-zero status");

    return hpx::util::report_errors();
}
