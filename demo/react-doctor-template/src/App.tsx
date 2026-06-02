import { useEffect, useState } from "react";

type ChildProps = {
  count: number;
  setCount: (next: number) => void;
};

function Child(props: ChildProps) {
  return (
    <button onClick={() => props.setCount(props.count + 1)}>
      Count: {props.count}
    </button>
  );
}

export function App() {
  const [count, setCount] = useState(0);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    if (count > 0) {
      setReady(true);
    }
  }, [count, ready]);

  return (
    <main>
      <h1>React Doctor Demo</h1>
      <Child count={count} setCount={setCount} />
      <p>{ready ? "ready" : "waiting"}</p>
    </main>
  );
}
