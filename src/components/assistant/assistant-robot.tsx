import Image from "next/image";
// رمز مساعد سِياق: الروبوت المعتمد من كريم (بلا عينين، وفي شاشته شعار سِياق). زخرفي؛ الاسم مكتوب تحته.
export function AssistantRobot({size}: {size: number}) {
  return <Image className="assistant-robot" src="/brand/assistant-robot.png" alt="" width={512} height={512} sizes={`${size}px`} loading="eager" draggable={false}/>;
}
