"""Train a lightweight (5-10 MB) Neural Engine-compatible aesthetic scoring model
and export it to SuperposeAI/Resources/SuperposeAesthetic.mlmodel.

Expected dataset structure:
    dataset/
      iyi/    (well-framed, sharp, balanced portrait & street photos -> target 0.90)
      kotu/   (poorly framed, tilted, blurry, or dark photos -> target 0.25)

Usage (Windows / Linux / Google Colab):
    pip install -r scripts/requirements-ml.txt
    python scripts/train_aesthetic_model.py --data dataset --epochs 12
"""

import argparse
from pathlib import Path

import coremltools as ct
from PIL import Image
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, Dataset
from torchvision import models, transforms


IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".heic"}


class AestheticFolderDataset(Dataset):
    def __init__(self, root_dir: Path, transform: transforms.Compose) -> None:
        self.samples: list[tuple[Path, float]] = []
        self.transform = transform

        for folder, target in [("iyi", 0.90), ("kotu", 0.25)]:
            class_dir = root_dir / folder
            if not class_dir.exists():
                continue
            for path in class_dir.rglob("*"):
                if path.suffix.lower() in IMAGE_EXTENSIONS:
                    self.samples.append((path, target))

        if not self.samples:
            raise ValueError(
                f"No images found in '{root_dir}/iyi' or '{root_dir}/kotu'."
            )

    def __len__(self) -> int:
        return len(self.samples)

    def __getitem__(self, idx: int) -> tuple[torch.Tensor, torch.Tensor]:
        path, target = self.samples[idx]
        with Image.open(path) as img:
            rgb = img.convert("RGB")
            tensor = self.transform(rgb)
        return tensor, torch.tensor([target], dtype=torch.float32)


class SuperposeAestheticNet(nn.Module):
    """MobileNetV3-Small regressor expecting [0, 1] RGB input (224x224)
    and outputting aestheticScore in [0, 1]."""

    def __init__(self) -> None:
        super().__init__()
        backbone = models.mobilenet_v3_small(
            weights=models.MobileNet_V3_Small_Weights.DEFAULT
        )
        in_features = backbone.classifier[0].in_features
        backbone.classifier = nn.Sequential(
            nn.Linear(in_features, 128),
            nn.Hardswish(),
            nn.Dropout(p=0.2),
            nn.Linear(128, 1),
            nn.Sigmoid(),
        )
        self.backbone = backbone
        self.register_buffer(
            "mean", torch.tensor([0.485, 0.456, 0.406]).view(1, 3, 1, 1)
        )
        self.register_buffer(
            "std", torch.tensor([0.229, 0.224, 0.225]).view(1, 3, 1, 1)
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        normalized = (x - self.mean) / self.std
        return self.backbone(normalized)


def train_model(data_dir: Path, epochs: int, batch_size: int, lr: float) -> SuperposeAestheticNet:
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Training on device: {device}")

    # Do NOT random-crop or rotate: framing & horizon are part of the aesthetic label.
    transform = transforms.Compose(
        [
            transforms.Resize((224, 224)),
            transforms.RandomHorizontalFlip(p=0.5),
            transforms.ToTensor(),
        ]
    )

    dataset = AestheticFolderDataset(data_dir, transform=transform)
    loader = DataLoader(dataset, batch_size=batch_size, shuffle=True, num_workers=0)
    print(f"Loaded {len(dataset)} images.")

    model = SuperposeAestheticNet().to(device)
    optimizer = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=1e-4)
    criterion = nn.SmoothL1Loss()

    model.train()
    for epoch in range(1, epochs + 1):
        running_loss = 0.0
        for images, targets in loader:
            images = images.to(device)
            targets = targets.to(device)

            optimizer.zero_grad()
            preds = model(images)
            loss = criterion(preds, targets)
            loss.backward()
            optimizer.step()

            running_loss += loss.item() * images.size(0)

        avg_loss = running_loss / len(dataset)
        print(f"Epoch {epoch:02d}/{epochs:02d} - loss: {avg_loss:.4f}")

    return model.cpu().eval()


def export_coreml(model: SuperposeAestheticNet, output_path: Path) -> None:
    example_input = torch.rand(1, 3, 224, 224)
    traced = torch.jit.trace(model, example_input)

    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.ImageType(
                name="image",
                shape=(1, 3, 224, 224),
                scale=1.0 / 255.0,
                color_layout=ct.colorlayout.RGB,
            )
        ],
        outputs=[ct.TensorType(name="aestheticScore")],
        convert_to="neuralnetwork",
        compute_units=ct.ComputeUnit.ALL,
    )
    mlmodel.author = "Superpose Labs"
    mlmodel.short_description = "On-device portrait & street aesthetic score regressor (0..1)."

    output_path.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(output_path))
    size_mb = output_path.stat().st_size / (1024 * 1024) if output_path.is_file() else 0.0
    print(f"Saved CoreML model to: {output_path} ({size_mb:.2f} MB)")


def main() -> None:
    parser = argparse.ArgumentParser(description="Train & export SuperposeAesthetic.mlmodel")
    parser.add_argument("--data", type=Path, default=Path("dataset"), help="Dataset folder with iyi/ and kotu/")
    parser.add_argument("--epochs", type=int, default=12, help="Number of training epochs")
    parser.add_argument("--batch-size", type=int, default=16, help="Training batch size")
    parser.add_argument("--lr", type=float, default=3e-4, help="Learning rate")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("SuperposeAI/Resources/SuperposeAesthetic.mlmodel"),
        help="Output .mlmodel path",
    )
    args = parser.parse_args()

    model = train_model(args.data, epochs=args.epochs, batch_size=args.batch_size, lr=args.lr)
    export_coreml(model, args.output)


if __name__ == "__main__":
    main()
